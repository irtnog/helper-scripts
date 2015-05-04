#!/usr/bin/env perl
# Copyright (C) 2009 Matthew X. Economou
# All rights reserved.
#
# Permission to use, copy, modify, and distribute this software
# for any purpose with or without fee is hereby granted, provided
# that the above copyright notice and this permission notice
# appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
# WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL
# THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
# CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
# LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
# NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
# CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
require 5.8.0;                   # Perl 5.8 required at a minimum
use strict;                      # paranoia settings
use warnings;
use Getopt::Long;                # command-line option parser
use Pod::Usage;                  # in-line program documentation
use Data::Dumper;                # pretty-print objects
use English '-no_match_vars';    # alias short variable names
use IO::Handle;                  # manage standard I/O streams
use File::Copy;                  # copy/move that can target handles
use File::Temp;                  # secure generation of scratch files
use Net::LDAP;                   # LDAP client
use Net::LDAP::Control::Paged;
use Net::LDAP::Constant('LDAP_CONTROL_PAGED');

# program version number
my $version = "0.5";

# program exit status code
my $exit_status = 0;

# reset problematic environment variables
delete @ENV{ 'IFS', 'CDPATH', 'ENV', 'BASH_ENV' };
$ENV{'PATH'} = "/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin";

# force real-time error output
STDERR->autoflush(1);

# enable additional security checks in File::Temp
File::Temp->safe_level(File::Temp::HIGH);

# program default settings (can be overriden by the config file or
# on the command line)
my $def_config_file   = "/usr/local/etc/list-exchange-recipients.conf";
my $def_recipient_map = "/usr/local/etc/postfix/exchange_recipients";
my $def_postmap_cmd   = "postmap";

# parse the command line options
my $opt_config_file;
my $opt_recipient_map;
my $opt_postmap_cmd;
my $verbose;
my $debug;
GetOptions(
    "configuration_file|configuration-file|configfile|conffile|cf=s" =>
      \$opt_config_file,
    "recipient_map|recipient-map|map|output=s"      => \$opt_recipient_map,
    "postmap_command|postmap-command|command|cmd=s" => \$opt_postmap_cmd,
    "v|verbose!"                                    => \$verbose,
    "quiet!"                                        => sub {
        if   ( $_[1] == 1 ) { $verbose = 0; }
        else                { $verbose = 1; }
    },
    "debug!"  => \$debug,
    "version" => sub {
        if ( $_[1] == 1 ) { print $version . "\n" and exit(0); }
    },
    "help|?" => sub {
        if ( $_[1] == 1 ) { pod2usage(1); }
    },
    "manual_page|manual-page|manualpage|man_page|man-page|manpage" => sub {
        if ( $_[1] == 1 ) { pod2usage( exitval => 1, verbose => 2 ); }
    }
) or pod2usage(2);

# set the recipient map filename
my $recipient_map =
  ( ( defined $opt_recipient_map ) ? $opt_recipient_map : $def_recipient_map );

# set the postmap command
my $postmap_cmd =
  ( ( defined $opt_postmap_cmd ) ? $opt_postmap_cmd : $def_postmap_cmd );

# read the optional configuration file, which only lists AD domains to
# export (plus the credentials necessary for accessing those domains)
my %domains = ();
my $config_file =
  ( ( defined $opt_config_file ) ? $opt_config_file : $def_config_file );
if ( -e $config_file )
{
    warn( "Reading the configuration file ", $config_file, "\n" )
      if ( $verbose or $debug );
    open( CONFIG, $config_file )
      or die("Error opening configuration file \"$config_file\": $ERRNO\n");
    while (<CONFIG>)
    {
        chomp;
        warn( "Config entry: ", $ARG, "\n" )
          if ($debug);
      CONFIG:
        {

            # skip empty lines or comment lines
            last CONFIG if m/^\s*(#|$)/;

            # three columns separated by whitespace: DNS domain name,
            # user name, and password; anything after the whitespace
            # following the username is assumed to be part of the
            # password; usernames with spaces in the DN must be
            # surrounded by double-quotes
            m/^(\S+)\s+"([^"]+)"\s+(.*)$/
              and $domains{$1} = [ $2, $3 ], last CONFIG;
            m/^(\S+)\s+(\S+)\s+(.*)$/
              and $domains{$1} = [ $2, $3 ], last CONFIG;
        }
    }
    close(CONFIG);
    warn( '%domains = ', Dumper(%domains), "\n" )
      if ($debug);
}

# read the remaining command line arguments, which list additional AD
# domains to export (and can override domain/credential tuples
# specified in the config file)
warn("Processing any remaining command-line arguments.\n")
  if ( $verbose or $debug );
warn( '@ARGV = ', Dumper(@ARGV), "\n" )
  if ($debug);
while ( $#ARGV >= 2 )
{
    my $domain   = shift @ARGV;
    my $user     = shift @ARGV;
    my $password = shift @ARGV;
    $domains{$domain} = [ $user, $password ];
}
warn( '%domains = ', Dumper(%domains), "\n" )
  if ($debug);
warn("Ignoring trailing command-line arguments.\n")
  if ( ( $#ARGV > 0 ) and ( $verbose or $debug ) );

# exit with an error if no domain/user/password tuples were specified,
# either in the configuration file or on the command line
die "No domains specified, exiting.\n"
  if ( !scalar(%domains) );

# loop through the domain list, building the recipient map as we go
warn("Processing the configured AD domains.\n")
  if ($debug);
my $domain;
my $credentials;
my @recipients = ();
while ( ( $domain, $credentials ) = each(%domains) )
{
    warn("Processing AD domain $domain.\n")
      if ( $verbose or $debug );
    push( @recipients, "# ---BEGIN DOMAIN $domain---\n\n" );

    # the LDAP search base is the domain NC
    my $base = "dc=" . $domain;
    $base =~ s/\./,dc=/g;
    warn( '$base = ', Dumper($base), "\n" )
      if ($debug);

    # connect to a domain controller
    warn( "Connecting to ",
          $domain, " via LDAP with DN ",
          $$credentials[0], " and password ",
          $$credentials[1], ".\n" )
      if ($debug);
    my $ldap = Net::LDAP->new($domain)
      or die( "Error connecting to ", $domain, ": ", $ERRNO, "\n" );
    warn( '$ldap = ', Dumper($ldap), "\n" ) if ($debug);
    my $mesg = $ldap->bind( dn       => $$credentials[0],
                            password => $$credentials[1] );
    warn( '$mesg = ', Dumper($mesg), "\n" ) if ($debug);
    die( "Bind to $domain failed: ",
         $mesg->code(), ", ", $mesg->error_text(), "\n" )
      if ( $mesg->code );

    # set up the LDAP query; exclude contact objects from the query
    # because they represent external addresses, not Exchange users
    warn("Setting up the LDAP query.\n") if ( $verbose or $debug );
    my $page = Net::LDAP::Control::Paged->new( size => 500 );
    my $filter = "(&(mailnickname=*)
					(|(&(objectCategory=person)(objectClass=user)
					    (!(homeMDB=*))(!(msExchHomeServerName=*)))
					  (&(objectCategory=person)(objectClass=user)
					    (|(homeMDB=*)(msExchHomeServerName=*)))
					  (objectCategory=group)
					  (objectCategory=publicFolder)
					  (objectClass=msExchDynamicDistributionList)))";

    # execute the query
    warn("Executing the query.\n")
      if ( $verbose or $debug );
    my $cookie;
    while (1)
    {
        warn( '$cookie = ', Dumper($cookie), "\n" )
          if ( $debug and !( undef $cookie ) );

        # perform the search
        if ( undef $cookie )
        {
            warn("Performing the search.\n")
              if ( $verbose or $debug );
        }
        else
        {
            warn("Continuing the search.\n")
              if ( $verbose or $debug );
        }
        $mesg = $ldap->search(
                               base    => $base,
                               filter  => $filter,
                               control => [$page],
                               attrs   => ["proxyAddresses"]
        );
        warn( '$mesg = ', Dumper($mesg), "\n" ) if ($debug);

        # only continue on LDAP_SUCCESS
        $mesg->code and last;

        # output this set of results
        warn("Processing results.\n")
          if ( $verbose or $debug );
        foreach my $result ( $mesg->entries )
        {

            # print a comment line with the DN of the mail-enabled
            # object
            my $dn = $result->dn();
            warn("Dumping email addresses for user $dn.\n")
              if ( $verbose or $debug );
            push( @recipients, "# " . $dn . "\n" );

            # print each SMTP address, followed by the keyword "OK"
            foreach my $address ( $result->get_value('proxyAddresses') )
            {

                # ignore non-SMTP addresses (e.g., X.500)
                if ( $address =~ m/^smtp:(.*)/i )
                {
                    warn("$dn: $1\n")
                      if ($debug);
                    push( @recipients, $1 . " OK\n" );
                }
            }

            # print a blank line for neatness' sake
            push( @recipients, "\n" );
        }
        warn("Finished results processing.\n")
          if ( $verbose or $debug );

        # exit the loop if this was the last page of results
        my ($resp) = $mesg->control(LDAP_CONTROL_PAGED) or last;
        warn( '$resp = ', Dumper($resp), "\n" )
          if ($debug);

        # save our place in the search results: the next loop
        # iteration will fetch the next page of search results
        $cookie = $resp->cookie or last;
        $page->cookie($cookie);
    }
    warn("Finished query execution.\n")
      if ( $verbose or $debug );

    # cleanly terminate the search in case of an abnormal exit
    if ($cookie)
    {
        warn("Query exit was abnormal; cleaning up.\n")
          if ( $verbose or $debug );
        $page->cookie($cookie);
        $page->size(0);
        $ldap->search(
                       base    => $base,
                       filter  => $filter,
                       control => [$page],
                       attrs   => ["proxyAddresses"]
        );
        die( "Query of $domain failed: ",
             $mesg->code(), ", ", $mesg->error_text(), "\n" );
    }

    # disconnect from the domain controller
    warn("Disconnecting from domain $domain.\n")
      if ( $verbose or $debug );
    $mesg = $ldap->unbind();
    warn( '$mesg = ', Dumper($mesg), "\n" )
      if ($debug);
    die( "Unbind from $domain failed: ",
         $mesg->code(), ", ", $mesg->error_text(), "\n" )
      if ( $mesg->code );
    $ldap->disconnect();
    warn("Completed processing of AD domain $domain.\n")
      if ( $verbose or $debug );
    push( @recipients, "# ---END DOMAIN $domain---\n\n" );
}

# backup the original file (if it exists) just in case postmap
# cannot process the new recipient map
warn("Copying existing recipient map to a temporary backup file.\n")
  if ( $verbose or $debug );
my $tmp = File::Temp->new(
                           TEMPLATE => 'list-exchange-recipients-XXXXX',
                           SUFFIX   => '.conf'
) or die( "Error creating temporary backup file: ", $ERRNO, "\n" );
$tmp->autoflush(1);
warn( "Temporary backup file name is \"",
      $tmp->filename(), "\"; starting copy.\n" )
  if ($debug);
copy( $recipient_map, $tmp )
  or die( "Error copying recipient map \"",
          $recipient_map, "\" to the temporary backup file \"",
          $tmp->filename(), "\": ", $ERRNO, "\n" );
warn("Backup successful.\n")
  if ($debug);
$tmp->seek( 0, 0 );    #rewind

# output the recipient map only if all the queries were successful
# to avoid overwriting the existing file with garbage;
warn( "Writing the recipient map ", $recipient_map, "\n" )
  if ( $verbose or $debug );
open( MAP, ">" . $recipient_map )
  or die( "Error opening recipient map \"",
          $recipient_map, "\" for writing: ",
          $ERRNO, "\n" );
print MAP @recipients;
close(MAP);

# process the file using the postmap command; if postmap fails,
# restore the backup
my @args = ( $postmap_cmd, $recipient_map );
warn( "Executing the command \"", @args, "\"." ) if ( $verbose or $debug );
if ( system(@args) != 0 )
{
    warn("Postmap failed; restoring the original recipient map.\n") if ($debug);
    copy( $tmp, $recipient_map )
      or die( "Error copying the temporary backup file \"",
              $tmp->filename(), "\" to recipient map \"",
              $recipient_map, "\": ", $ERRNO, "\n" );
    die( "Execution of command \"",
         @args, "\" failed: ", $CHILD_ERROR,
         "\n(Recovery steps initiated.)\n" );
}
exit $exit_status;
__END__

=head1 NAME

list-exchange-recipients - Export Exchange address lists to a Postfix recipient map

=head1 SYNOPSIS

list-exchange-recipients [options] [<domain name> <username> <password>]*

At least one domain name/username/password tuple must be specified,
either in the configuration file or on the command line.  The
domain name must be in DNS format, not NetBIOS (e.g., "example.com",
not "EXAMPLE").  The username may be an LDAP distinguished name
(e.g., "CN=List Recipients,CN=Users,DC=example,DC=com") or a
Kerberos user principal name (e.g., "listrecipients@EXAMPLE.COM").
This account does not need any special privileges in the domain.

=head1 DESCRIPTION

This program connects to an Active Directory domain that hosts an
Exchange 6.x organization and exports the address list in a format
readable by Postfix's relay recipient verification feature.  Sites
that use Postfix mail relays with their Exchange servers can use this
to reduce the load on their mail relays due to non-delivery reports
for invalid recipients.

Command-line options may be abbreviated.  Those options toggling
behavior can be toggled off by prefixing the option with "no",
e.g. "--no-verbose".

=over 8

=item B<--configuration-file> I<file>

Changes the location of the configuration file.  By default, this
program attempts to read its configuration from
"/usr/local/etc/list-exchange-recipients.conf".

=item B<--recipient-map> I<file>

Changes the location of the recipient map output by this program.  By
default, it attempts to write the recipient map to
"/usr/local/etc/postfix/exchange_recipients".

=item B<--postmap-command> I<pathname>

This program resets the executable search path as a security
precaution (see ENVIRONMENT below).  If the "postmap" command is not
located in one of the standard directories, use this option to set
its full pathname (e.g., to "/opt/local/bin/postmap").

=item B<--verbose> or B<--quiet>

Increase or decrease the amount of progress information displayed
by the program.

=item B<--debug>

Display additional diagnostic information (implies --verbose).

=item B<--version>

Prints the program version number and exits.

=item B<--help> or B<--?>

Prints a brief help message and exits.

=item B<--manual>

Prints the manual page and exits.

=back

=head1 IMPLEMENTATION NOTES

TODO

=head1 ENVIRONMENT

=over 8

=item B<PATH>

This program resets the executable search path to
"/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin" as a
security precaution.

=item B<IFS>, B<CDPATH>, B<ENV>, B<BASH_ENV>

This program deletes the above environment variables as a security
precaution.

=back

=head1 FILES

=over 8

=item B</usr/local/etc/list-exchange-recipients.conf>

This is the default location of the B<list-exchange-recipients.conf>
program configuration file.  This file lists the Active Directory
domains to process together with the credentials necessary to access
that domain.  On one line, list the DNS domain name of the Active
Directory domain, the distinguished name (DN) of the user account
used to log into the domain, and that account's password, separated
by spaces.  If the user DN includes spaces, surround the user DN with
double quotes (").  The first non-whitespace character after the
username plus anything thereafter is considered the password. 

=item B</usr/local/etc/postfix/exchange_recipients>

This is the default location of the Postfix recipient map output by
this program.  To configure Postfix to use this map, use the postconf
command to set the relay_recipient_maps variable.  The output file is
in the Postfix hash table format.

=back

=head1 SEE ALSO

L<Net::LDAP>, L<GSSAPI>

=head1 AUTHOR

Matthew X. Economou, xenophon@irtnog.org

=head1 BUGS

This program does not make the most efficient use of memory.

External email addresses will appear in the recipient map for
users whose mail is forwarded to another (non-Exchange) mailbox.
This is probably caused by a problem with the LDAP search filter
used by this program.

#!/bin/sh

PROJECT="$1"
PROJECT_NAME="$2"

# Create the Mercurial repository and add it to the hgweb browser
# (https://dev.irtnog.org/hg/).
sudo -u hg hg init ~hg/repos/${PROJECT}
echo "${PROJECT} = /usr/local/hg/repos/${PROJECT}" >> ~hg/hgweb.config

# Create the matching Trac environment.
trac-admin ~trac/${PROJECT} initenv "${PROJECT_NAME}" sqlite:db/trac.db hg ~hg/repos/${PROJECT}

# Configure a Mercurial on-commit hook that updates the Trac database
# whenever someone pushes new deltas to the master repository.
ed <<EOF
a
[hooks]
commit = python:tracext.hg.hooks.add_changesets
changegroup = python:tracext.hg.hooks.add_changesets

[trac]
env = /usr/local/www/trac/${PROJECT}
trac-admin = /usr/local/bin/trac-admin
.
w /usr/local/hg/repos/${PROJECT}/.hg/hgrc
q
EOF
ed ~trac/${PROJECT}/conf/trac.ini <<EOF
a
[hg]
show_rev = yes
node_format = short

[components]
tracext.hg.* = enabled
tracopt.ticket.commit_updater.* = enabled

.
w
q
EOF

# Fix up the file system permissions so that users hg, trac, and www
# can all access the necessary files.
chown -R trac:trac ~trac/${PROJECT}
find ~trac -type  f -name trac.ini -exec chmod 644 '{}' \;
find ~trac -type f -name trac.db -exec chmod 664 '{}' \;
find ~trac -type d -name db -exec chmod 775 '{}' \;
find ~trac -name .egg-cache -exec chmod -R 775 '{}' \;

# Publish the new Trac project to its own WSGI process group and
# script alias.  Note that web app content is served statically off
# the file system for performance reasons.
trac-admin ~trac/${PROJECT} deploy /usr/local/www/apache22/${PROJECT}
ed /usr/local/etc/apache22/Includes/vhost:dev.irtnog.org.conf <<EOF
/authopenid
i
	Alias /${PROJECT}/chrome/common /usr/local/www/apache22/${PROJECT}/htdocs/common
	Alias /${PROJECT}/chrome/site /usr/local/www/apache22/${PROJECT}/htdocs/site
	WSGIDaemonProcess ${PROJECT} user=trac group=trac threads=5
	WSGIScriptAlias /${PROJECT} /usr/local/www/apache22/${PROJECT}/cgi-bin/trac.wsgi

	<Directory /usr/local/www/apache22/${PROJECT}/cgi-bin>
		<Files trac.wsgi>
			WSGIProcessGroup ${PROJECT}
			WSGIApplicationGroup %{GLOBAL}
			Order deny,allow
			Allow from all
		</Files>
	</Directory>

	<Directory /usr/local/www/apache22/${PROJECT}/htdocs>
		Order deny,allow
		Allow from all
	</Directory>

.
wq
EOF

# Customize the Trac project's permissions:
# * The "admin" role has full administrative privileges.
# * The "developer" can edit or close tickets in addition to full
#   control over the wiki.
# * Because we're using OpenID and controlling access from within the
#   Trac project itself, anyone can log into the Trac project, so we
#   remove authenticated users' ability to edit/close tickets or
#   modify wiki content to curtail potential abuse.
trac-admin ~trac/${PROJECT} permission add admin TRAC_ADMIN
trac-admin ~trac/${PROJECT} permission add developer TICKET_MODIFY WIKI_ADMIN
trac-admin ~trac/${PROJECT} permission remove authenticated TICKET_MODIFY WIKI_CREATE WIKI_MODIFY

# Create the first admin for the Trac project.  Note that the
# Mercurial repository will inherit its first admin from the "hgadmin"
# management repository.
trac-admin ~trac/${PROJECT} permission add 'https://profile.irtnog.org/index.php?user=xenophon' admin

# Loading SSH Keys on a Mac at Time of Console Login

CAUTION:
[SSH Agent Forwarding considered harmful](http://heipei.github.io/2015/02/26/SSH-Agent-Forwarding-considered-harmful/)

Gee, wouldn't it be nice if Mac OS X offered a simple way to load
(additional) SSH keys when you log into a console session?  Of course,
one doesn't simply add suitable commands to `~/.login`, because the
old ways are old and therefore much be replaced with something new
even though the old ways worked just fine thank you very much.  Hence,
launchd (which is bad enough) and XML (compounding the error).

## Installation

1. Modify `add-ssh-keys.sh` as appropriate for your environment.

2. Copy `add-ssh-keys.sh` to `~/bin/` and make sure it's executable.

3. Copy `org.irtnog.add-ssh-keys.plist` to `~/Library/LaunchAgents/`.

4. Profit... but log out and log back in, first.

## Caveats

I have an unreasonably large list of SSH private keys going back
several years.  While I doubt I need them all, they persist in my
configuration files just in case I need to access some old system that
I have since completely forgotten about.  This can cause login
problems for some other systems (the one's I didn't forget about),
where each key-based authentication attempt might be considered a
separate login attempt for policy reasons (i.e., only so many failed
login attempts are allowed before you get booted off the system or
blacklisted).  As a workaround, add lines similar to the following to
`~/.ssh/config` to alter or bypass SSH key authentication:

```
host somethingsomethingsomething.darkside:
	PreferredAuthentications keyboard-interactive,password

host somethingsomethingsomething.complete:
	IdentityFile ~/.ssh/something.pem
```

(Boy, howdy, ICANN'll give a botique TLD to just about anybody these
days.)

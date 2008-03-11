# pretty login screen..
echo -e "" > /etc/issue
echo -e "           888     888 \\033[0;32md8b\\033[0;39m         888    " >> /etc/issue
echo -e "           888     888 \\033[0;32mY8P\\033[0;39m         888    " >> /etc/issue
echo -e "           888     888             888    " >> /etc/issue
echo -e "   .d88b.  Y88b   d88P 888 888d888 888888 " >> /etc/issue
echo -e "  d88''88b  Y88b d88P  888 888P'   888    " >> /etc/issue
echo -e "  888  888   Y88o88P   888 888     888    " >> /etc/issue
echo -e "  Y88..88P    Y888P    888 888     Y88b.  " >> /etc/issue
echo -e "   'Y88P'      Y8P     888 888      'Y888 " >> /etc/issue
echo -e "" >> /etc/issue
echo -e "  Admin node \\\\n " >> /etc/issue
echo -e "" >> /etc/issue
echo -e "  Virtualization just got the \\033[0;32mGreen Light\\033[0;39m" >> /etc/issue
echo -e "" >> /etc/issue
cp /etc/issue /etc/issue.net

# postgres commands used at first boot to setup the database
cat > /usr/share/ovirt-wui/psql.cmds << \EOF
CREATE USER ovirt WITH PASSWORD 'v23zj59an';
CREATE DATABASE ovirt;
GRANT ALL PRIVILEGES ON DATABASE ovirt to ovirt;
CREATE DATABASE ovirt_test;
GRANT ALL PRIVILEGES ON DATABASE ovirt_test to ovirt;
EOF
chmod a+r /usr/share/ovirt-wui/psql.cmds

# turn on tftp in xinetd
sed -i -e 's/\(.*\)disable\(.*\)= yes/\1disable\2= no/' /etc/xinetd.d/tftp

# setup an NTP step-ticker
echo "0.fedora.pool.ntp.org" >> /etc/ntp/step-tickers

# setup gssapi in the mech_list
if [ `egrep -c '^mech_list: gssapi' /etc/sasl2/libvirt.conf` -eq 0 ]; then
   sed -i -e 's/^\([[:space:]]*mech_list.*\)/#\1/' /etc/sasl2/libvirt.conf
   echo "mech_list: gssapi" >> /etc/sasl2/libvirt.conf
fi

# a script to create the default principals we need
cat > /root/create_default_principals.py << \EOF
#!/usr/bin/python

import krbV
import os, string, re
import socket
import shutil

def kadmin_local(command):
        ret = os.system("/usr/kerberos/sbin/kadmin.local -q '" + command + "'")
        if ret != 0:
                raise

default_realm = krbV.Context().default_realm

# here, generate the libvirt/ principle for this machine, necessary
# for taskomatic and host-browser
this_libvirt_princ = 'libvirt/' + socket.gethostname() + '@' + default_realm
kadmin_local('addprinc -randkey +requires_preauth ' + this_libvirt_princ)
kadmin_local('ktadd -k /usr/share/ovirt-wui/ovirt.keytab ' + this_libvirt_princ)

# We need to replace the KrbAuthRealms in the ovirt-wui http configuration
# file to be the correct Realm (i.e. default_realm)
ovirtconfname = '/etc/httpd/conf.d/ovirt-wui.conf'
ipaconfname = '/etc/httpd/conf.d/ipa.conf'

# make sure we skip this on subsequent runs of this script
if string.find(file(ipaconfname, 'rb').read(), '<VirtualHost *:8089>') < 0:
    ipaconf = open(ipaconfname, 'r')
    ipatext = ipaconf.readlines()
    ipaconf.close()

    ipaconf2 = open(ipaconfname, 'w')
    print >>ipaconf2, "Listen 8089"
    print >>ipaconf2, "NameVirtualHost *:8089"
    print >>ipaconf2, "<VirtualHost *:8089>"
    for line in ipatext:
        newline = re.sub(r'(.*RewriteCond %{HTTP_HOST}.*)', r'#\1', line)
        newline = re.sub(r'(.*RewriteRule \^/\(.*\).*)', r'#\1', newline)
        newline = re.sub(r'(.*RewriteCond %{SERVER_PORT}.*)', r'#\1', newline)
        newline = re.sub(r'(.*RewriteCond %{REQUEST_URI}.*)', r'#\1', newline)
        ipaconf2.write(newline)
    print >>ipaconf2, "</VirtualHost>"
    ipaconf2.close()

if string.find(file(ovirtconfname, 'rb').read(), '<VirtualHost *:80>') < 0:
    ovirtconf = open(ovirtconfname, 'r')
    ovirttext = ovirtconf.readlines()
    ovirtconf.close()

    ovirtconf2 = open(ovirtconfname, 'w')
    print >>ovirtconf2, "NameVirtualHost *:80"
    print >>ovirtconf2, "<VirtualHost *:80>"
    for line in ovirttext:
        newline = re.sub(r'(.*)KrbAuthRealms.*', r'\1KrbAuthRealms ' + default_realm, line)
        newline = re.sub(r'(.*)Krb5KeyTab.*', r'\1Krb5KeyTab /etc/httpd/conf/ipa.keytab', newline)
        ovirtconf2.write(newline)
    print >>ovirtconf2, "</VirtualHost>"
    ovirtconf2.close()
EOF
chmod +x /root/create_default_principals.py

# set up the yum repos
cat > /etc/yum.repos.d/freeipa.repo << \EOF
[freeipa]
name=FreeIPA Development
baseurl=http://freeipa.com/downloads/devel/rpms/F7/$basearch/
enabled=1
gpgcheck=0
EOF

cat > /etc/yum.repos.d/ovirt-management.repo << \EOF
[ovirt-management]
name=ovirt-management
baseurl=http://ovirt.et.redhat.com/repos/ovirt-management-repo/$basearch/
enabled=1
gpgcheck=0
EOF
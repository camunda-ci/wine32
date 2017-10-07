#!/bin/bash

# Define sets of 32 bit packages in order of build dependencies
declare -a arr=(
  "dbus-c++-devel libxml++-devel scons"
  "libffado-devel"
  "jack-audio-connection-kit-devel"
  "portaudio-devel"
  "openal-soft nss-mdns"
  "wine"
)

#declare -a arr=(
#  "dbus-c++-devel libxml++-devel scons"
#)

len=${#arr[@]}

# Rebuild each set (install build dependencies as we go)
for (( i=0; i<${len}; i++ ));
do
  j=$((i+1))
  echo "Rebuilding package set $j: ${arr[$i]}..."
  mkdir -p "set$j/rpmbuild"
  yumdownloader -q --source --destdir=set$j ${arr[$i]}
  # Custom spec file...
  if [ -f set$j/custom/*.spec ]
  then
    echo "(we are using a custom spec file)"
    rpm --define "_topdir $PWD/set$j/rpmbuild" -i set$j/*.src.rpm
    cp -f set$j/custom/*.spec set$j/rpmbuild/SPECS
    yum-builddep -q -y set$j/rpmbuild/SPECS/*.spec
    linux32 rpmbuild --quiet --target=i686 --define "_topdir $PWD/set$j/rpmbuild" --define "dist .el7" --ba set$j/rpmbuild/SPECS/*.spec
  # ...or just rebuild
  else
    yum-builddep -q -y set$j/*.src.rpm
    linux32 rpmbuild --quiet --rebuild --target=i686 --define "_topdir $PWD/set$j/rpmbuild" --define "dist .el7" --ba set$j/*.src.rpm
  fi
  # No need to install last set
  if [ $i -lt $((len-1)) ]
  then
    echo "Installing package set $j: ${arr[$i]}..."
    yum -q -y install set$j/rpmbuild/RPMS/*/*.rpm
  fi
done

# Build release RPM
echo "Building release RPM..."
rpmbuild --quiet --define "_topdir $PWD/release" --ba release/SPECS/*.spec
mv release/RPMS/*/*.rpm $PWD
ln -s *release*.rpm $CI_PROJECT_NAME-release.rpm

# Move RPMs to public dir
mkdir -p public/7/i386
mv set*/rpmbuild/RPMS/*/*.rpm public/7/i386
mv *release*.rpm  public/7/i386

# Sign RPM files
echo -e "%_signature gpg" >> $HOME/.rpmmacros
echo -e "%_gpg_path /root/.gnupg" >> $HOME/.rpmmacros
echo -e "%_gpg_name $GPG_NAME" >> $HOME/.rpmmacros
echo -e "%_gpgbin /usr/bin/gpg" >> $HOME/.rpmmacros
echo -e "%_gpg_digest_algo sha256" >> $HOME/.rpmmacros

echo "$GPG_PUBLIC_KEY" > /tmp/public
echo "$GPG_PRIVATE_KEY" > /tmp/private
gpg --allow-secret-key-import --import /tmp/private
rpm --import /tmp/public

for f in public/7/i386/*.rpm
do
  echo "GPG signing $f..."
expect <(cat <<EOD
spawn rpm --resign $f
expect -exact "Enter pass phrase: "
send -- "$GPG_PASS_PHRASE\r"
expect eof
EOD
)
done

# Create yum repo
createrepo public/7/i386

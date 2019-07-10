#!/bin/sh

VERSION="20190521"

export IFS="
"

if [ "_${1}" == "_" ] ; then
	echo "No input file"
	exit 1
fi

FILE=${1}
STAGE="`mktemp -d /tmp/stage.XXXXXX`" 

echo "Use: ${STAGE}"

NAME="`egrep ^NAME ${FILE} | awk '{print $2}'`"
VERSION="`egrep ^VERSION ${FILE} | awk '{print $2}'`"
MAINTAINER="`egrep ^MAINTAINER ${FILE} | awk '{print $2}'`"
PACKAGES="`egrep ^INSTALL ${FILE} | cut -d" " -f2-`"
REPO="`egrep "^REPO " ${FILE} | cut -d" " -f2-`"
REPO_URL="`egrep ^REPO_URL ${FILE} | cut -d" " -f2-`"
BUILDS="`egrep "^BUILD " ${FILE} | cut -d" " -f2-`"
BUILDOPT="`egrep "^BUILD_OPTIONS" ${FILE} | cut -d" " -f2-`"
BUILDJAILZFS="`egrep ^ZFSPOOL ${FILE} | cut -d" " -f2-`"

grep ^RUN ${FILE} | cut -d" " -f2- >> ${STAGE}/+POST_INSTALL

for file in `grep ^COPY ${FILE}` ; do
	src="`echo ${file} | awk '{print $2}' `"
	src_base="`basename ${src}`"
	tgt="`echo ${file} | awk '{print $3}' `"
	target="`dirname ${tgt}`"
	mkdir -p ${STAGE}/${target}
	cp ${src} ${STAGE}/${tgt}
#	echo "${target}/${src_base}" >> ${STAGE}/plist	
done

for file in `grep ^SCOPY ${FILE}` ; do
	src="`echo ${file} | awk '{print $2}' `"
	src_base="`basename ${src}`"
	tgt="`echo ${file} | awk '{print $3}' `"
	target="`dirname ${tgt}`"
	mkdir -p ${STAGE}/${target}
	echo "Need password to decrypt file: ${src}" 
	openssl enc -d -aes256 -in ${src} -out ${STAGE}/${tgt}
#	echo "${target}/${src_base}" >> ${STAGE}/plist	
done

cat >> ${STAGE}/+MANIFEST <<_EOF
name: ${NAME}
version: "${VERSION}"
origin: jail/${NAME}
comment: "automates stuff"
desc: "automates tasks which can also be undone later"
maintainer: ${MAINTAINER}
www: https://doe.it
prefix: /
_EOF

IFS=" "

if [ "_${BUILDS}" != "_" ] ; then
	if [ "_{BUILDOPT}" != "_" ]  ; then
		bjail="`/vagrant_data/mj.sh get-bjail-name`"
		if [ "_${bjail}" == "_No build jail found" ] ; then
			echo "${bjail}"
			exit 1
		fi
		rm /${bjail}/etc/make.conf
		for buildopt in ${BUILDOPT}; do 
			echo ${buildopt} >> /${bjail}/etc/make.conf
		done
	fi

	for build in ${BUILDS} ; do
		pkg="`basename ${build}`"
##
## TODO: remove data fragment/replace
##
		mj.sh buildpkg build ${build} ${BUILDJAILZFS}
	done
	mkdir -p ${STAGE}/tmp
	/usr/bin/find /${bjail}/tmp -name "*.txz" -type f -exec cp {} ${STAGE}/tmp \;
	mkdir -p ${STAGE}/etc
	/usr/bin/find /${bjail}/tmp -name "*.txz" -type f -exec echo "/usr/sbin/pkg install -y /tmp/{}" \; | sed -e "s#/${bjail}/tmp/##" >> ${STAGE}/etc/rc.local
	echo 'echo "Additional packages needs to install, please restart (or run now /etc/rc.local)"' >> ${STAGE}/+POST_INSTALL
	echo '/bin/rm /etc/rc.local' >> ${STAGE}/etc/rc.local
fi

find ${STAGE} -type f \! -name "+POST_INSTALL" -a \! -name "+MANIFEST" -a \! -name "plist" -print | sed -e "s#${STAGE}##g" >> ${STAGE}/plist

if [ "_${REPO}" == "_" ] ; then
	REPO="latest"
fi
if [ "_${REPO_URL}" == "_" ] ; then
	REPO_URL='pkg+http://pkg.FreeBSD.org/${ABI}'

	mkdir -p /usr/local/etc/pkg/repos
	cat > /usr/local/etc/pkg/repos/mj-build.conf <<_EOF
mj-build: {
  url: "${REPO_URL}/${REPO}",
  mirror_type: "srv",
  signature_type: "fingerprints",
  fingerprints: "/usr/share/keys/pkg",
  enabled: yes
}
_EOF

fi

pkg update -r mj-build
echo "deps: {" >> ${STAGE}/+MANIFEST
for pkg in ${PACKAGES} ; do
	# echo "pkg rquery "  %n: { version: \"%v\", origin: %o }" firstboot-pkgs >> ${STAGE}/+MANIFEST
	echo "`pkg rquery -r mj-build '%n: {version: %v, origin: %o}' ${pkg}`" >> ${STAGE}/+MANIFEST
done
echo "}" >> ${STAGE}/+MANIFEST

pkg create -m ${STAGE}/ -r ${STAGE}/ -p ${STAGE}/plist -o .

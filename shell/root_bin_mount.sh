#!/bin/sh

VERSION="20190509"
option="${1}"

if [ "_${2}" != "_" ] ; then
	path="${2}"
else 
	echo "missing parameter"
	exit 1
fi

case ${option} in
        start)
                for dir in bin sbin lib libexec usr/include usr/bin usr/sbin usr/share usr/lib usr/lib32 usr/libexec usr/libdata; do /bin/mkdir -p ${path}/${dir}; /sbin/mount -t nullfs -o ro /${dir} ${path}/${dir}; done
        ;;
        stop)
                for dir in bin sbin lib libexec usr/include usr/bin usr/sbin usr/share usr/lib usr/lib32 usr/libexec usr/libdata; do /sbin/umount -f ${path}/${dir}; /bin/rmdir ${path}/${dir}; done
		/sbin/umount -f ${path}/dev
        ;;
        *)
        ;;
esac

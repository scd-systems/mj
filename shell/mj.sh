#!/bin/sh

VERSION="20190531"

help() {
        # echo "Usage: ${0} <ZFSPOOL> <JAILNAME> <INTERFACE> <IP>"
        cat <<_EOF
Usage: ${0} <COMMAND> <PARAMETER>

COMMANDS:
	create
	delete

PARAMETERS
	create
		ZPOOL		= Name of the zfs pool for the jail dataset
		JAILNAME	= Name of the Jail, will also be used as hostname
		INTERFACE	= Name of the Interface which will be used for listen
		IP		= IPv4 address of the Jail
		JPKG		= Configuration Package
	
	buildpkg
		JAILNAME	= Name of the build jail (use create if jail does not exists)
		PORTS		= Name of the Port to build (origin format: category/name)
		ZPOOL		= Name of the zfs pool for the build jail (optional)

	get-bjail-name
				= get path of current build jail
	template
				= create jfile template
_EOF

}

JMOUNT_BIN=/root/bin/mount.sh

create() {
	zfs create ${ZPOOL}/${J}
	mkdir -p ${JDIR}/dev ${JDIR}/root ${JDIR}/var ${JDIR}/tmp
	chmod 1777 ${JDIR}/tmp
	mtree -f /etc/mtree/BSD.var.dist -u -p ${JDIR}/var
	tar -C ${JDIR} -xvzf /usr/freebsd-dist/base.txz etc/
	cp /etc/resolv.conf ${JDIR}/etc
	cp /etc/localtime ${JDIR}/etc
	echo "hostname=\"${JHNAME}\"" > ${JDIR}/etc/rc.conf
	echo "syslogd_flags=\"-ss\"" >> ${JDIR}/etc/rc.conf
	echo "syslogd_enable=\"YES\"" >> ${JDIR}/etc/rc.conf
	echo "rpcbind_enable=\"NO\"" >> ${JDIR}/etc/rc.conf
	echo "sendmail_enable=\"NONE\"" >> ${JDIR}/etc/rc.conf
	echo "`uname -r`" > ${JDIR}/etc/freebsd-release
	touch ${JDIR}/etc/fstab
	cat >> /etc/jail.conf <<_EOF
${J} {
	path = "${JDIR}";
	exec.start = "/bin/sh /etc/rc";
	exec.stop = "/bin/sh /etc/rc.shutdown";
        exec.prestart = "${JMOUNT_BIN} start \${path}";
        exec.poststop = "${JMOUNT_BIN} stop \${path}";
        host.hostname = "\${name}";
	interface = "${INT}";
	ip4.addr = "${IPADDR}";
        persist;
}
_EOF

}
install(){
	/sbin/zfs snap -r ${ZPOOL}/${J}@stage0
	if [ "_${JPKG}" != "_" ] ; then
		echo "Inject ${JPKG} into jail"
		/bin/cp ${JPKG} ${JDIR}/tmp
		/usr/sbin/jail -c -J ./${J}.start.conf \
			name=${J} \
			path=${JDIR} \
			exec.clean \
			mount.devfs \
			exec.prestart="${JMOUNT_BIN} start ${JDIR}" \
			host.hostname=${J} \
			interface=${INT} \
			ip4.addr=${IPADDR} \
			persist \
			exec.stop="/bin/sh /etc/rc.shutdown" \
			exec.start="export ASSUME_ALWAYS_YES=YES; /usr/sbin/pkg install /tmp/${JPKG}"
		/usr/sbin/jail -r ${J}
		${JMOUNT_BIN} stop ${JDIR}
		/sbin/zfs snap -r ${ZPOOL}/${J}@stage1
	fi
}

buildpkg(){
	/usr/sbin/service jail onestart ${J}
	/usr/sbin/jexec ${J} portsnap auto
	for port in ${PORTS} ; do
		/usr/sbin/jexec build /bin/sh -c "export BATCH=1; cd /usr/ports/${port} && /usr/bin/make missing > /tmp/missing && if [ -s /tmp/missing ] ; then pkg install -y `cat /${ZPOOL}/${J}/tmp/missing`; fi && /usr/bin/make deinstall install clean && pkg create -o /tmp ${port}"
	done	
	/usr/sbin/service jail onestop ${J}
}


case ${1} in
	create)
		if [ $# -lt 4 ] ; then
		        echo "parameter missing"
		        help
		        exit 1
		fi
		export J="${3}"
		export ZPOOL="${2}"
		export JDIR="/${ZPOOL}/${J}"
		export JHNAME="${J}"
		export INT="${4}"
		export IPADDR="${5}"
		export JPKG="${6}"
		create
		install
	;;
	delete)
	;;
	buildpkg)
		export J="${2}"
		export PORTS="${3}"
		export ZPOOL="${4}"
		RET="`${0} get-bjail-name`"
		if [ "_${RET}" == "_" ] ; then	
			zfs set mj:build-jail=true ${ZPOOL}/${J}
		fi
		buildpkg
	;;
	get-bjail-name)
		RET="`/sbin/zfs get all | grep 'mj:build-jail' | grep 'true' | grep -v "@" | /usr/bin/awk '{print $1}'`"
		if [ "_${RET}" != "_" ] ; then	
			echo ${RET}
			exit 0
		else
			echo "No build jail found"
			exit 1
		fi
	;;
	template)
		if [ ! -e JFILE ] ; then
			cat >> JFILE <<_EOF
MAINTAINER `id -c`
NAME template
VERSION `date +%Y%m%d`

REPO latest
INSTALL pkg
RUN echo "template"

_EOF
		else
			echo "JFILE already found, will not overwrite"
		fi
	;;
	*)
		help
		exit 0
	;;
esac


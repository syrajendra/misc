#!/bin/sh

DRY_RUN=0
USER=`id -u -n`

OS=`uname -s`
MACHINE=`uname -m`

if [ ${OS} = "FreeBSD" ] ; then
    OS_ID=`uname -r | sed -e 's/[-_].*//' | sed -e 's/\..*// '`
elif [ ${OS} = "Darwin" ]; then
    OS_ID=`uname -r`
elif [ $OS = "Linux" ]; then
    if [ -f /etc/redhat-release ]; then
      # Redhat, Centos and similar
      OS_ID=`cat /etc/redhat-release | awk ' { print $1"-"$3 } ' | tr '[:upper:]' '[:lower:]'`
    elif [ -f /etc/os-release ]; then
      # Ubuntu
      OS_ID=`cat /etc/os-release | grep VERSION_ID | awk -F \" '{ print $2 }'`
      OS_ID="ubuntu-${OS_ID}"
    fi
else
  echo "Unknow platform"
  exit 1
fi
TOP_DIR="$PWD"


# Edit below for different versions of perl ###
PERL_VERSION="5.24.0"
PERL_DOWNLOAD_CMD="wget http://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz"
if [ $OS = "Linux" ]; then
	PERL_MODULES="Crypt::SSLeay Date::Manip DBI JSON DBD::mysql Log::Log4perl"
elif [ $OS = "FreeBSD" ]; then
	if [ $OS_ID = "7" ]; then
		PERL_MODULES=""
	else
		PERL_MODULES=""
	fi
fi
###########################################################################################

PERL_ZIP_FILE=`basename $(echo "$PERL_DOWNLOAD_CMD" | sed s/wget\ //g)`
PERL_FILE=`echo $PERL_ZIP_FILE | sed s/.tar.*//g`
SRC=$TOP_DIR/perl/${PERL_VERSION}/src
BUILD=$TOP_DIR/perl/${PERL_VERSION}/build/${OS}/${OS_ID}/${MACHINE}
TIMESTAMP=`date +%s`
LOG_FILE=$BUILD/perl_${TIMESTAMP}.log
LOG_CMD=" >> $LOG_FILE 2>&1 "
INSTALL=$TOP_DIR/$OS/$OS_ID/${MACHINE}/perl/$PERL_VERSION
CPANM_DOWNLOAD_INSTALL_CMD="curl -L http://cpanmin.us | $INSTALL/bin/perl - App::cpanminus"
CPANM=$INSTALL/bin/cpanm

if [ $OS = "Linux" ]; then
	MAKE="make"
	# CPUs = Threads per core X cores per socket X sockets
	CORES_PER_CPU=`cat /proc/cpuinfo | grep -m 1 'cpu cores' | awk '{ print $4 }'`
	TOTAL_CPUS=`cat /proc/cpuinfo | grep processor | wc -l`
	if [ "$CORES_PER_CPU" = "0" ]; then
		CORES_PER_CPU=1
	fi
	CPUS=$(($CORES_PER_CPU * $TOTAL_CPUS))
	CPUS=$TOTAL_CPUS
elif [ $OS = "FreeBSD" ]; then
	MAKE="gmake"
	CPUS=`sysctl hw.ncpu|sed s/hw.ncpu:\ //g`
else
	echo "Platform not supported"
	exit 1
fi

run_cmd() {
	echo "CMD: $@"
	if [ "x$DRY_RUN" = "x" ] || [ "x$DRY_RUN" = "x0" ]; then
		if eval "$@"; then
			echo "Status : Success"
		else
			echo "Status : Failed"
			exit 1
		fi
	else
		echo "Dry run success"
	fi
}

init() {
	run_cmd "mkdir -p $SRC"
	run_cmd "mkdir -p $BUILD"
}

get_src() {
	# Get source
	if [ ! -f $SRC/$PERL_ZIP_FILE ]; then
		run_cmd "cd $SRC && $PERL_DOWNLOAD_CMD $LOG_CMD"
	fi

	cmd="cd $SRC && tar -xzvf $PERL_ZIP_FILE"
	if [ ! -d $SRC/$PERL_FILE ]; then
		run_cmd "$cmd $LOG_CMD"
	fi
}


build_install() {
	# Build
	if [ ! -d $BUILD/$PERL_FILE ]; then
		cmd="cp -rf $SRC/$PERL_FILE $BUILD/."
		run_cmd "$cmd $LOG_CMD"
	fi

	cmd="cd $BUILD/$PERL_FILE && ./Configure -des -Dprefix=$INSTALL -Dusethreads"
	run_cmd "$cmd $LOG_CMD"

	cmd="cd $BUILD/$PERL_FILE && $MAKE -j $CPUS"
	run_cmd "$cmd $LOG_CMD"
	run_cmd "mkdir -p $INSTALL"
	cmd="cd $BUILD/$PERL_FILE && $MAKE install"
	run_cmd "$cmd $LOG_CMD"
	echo "Successfully installed perl-$PERL_VERSION"
}

install_cpan() {
	# Install cpanm
	PERL=$INSTALL/bin/perl
	if [ -f $PERL ]; then
		if [ ! -f $CPANM ]; then
			cmd="$CPANM_DOWNLOAD_INSTALL_CMD"
			run_cmd "$cmd $LOG_CMD"
		else
			echo "Cpanm command already installed. Skipping"
		fi
	else
		echo "Perl-$PERL_VERSION not built correctly !!!"
		exit 1
	fi
}

install_modules() {
	# Install modules
	if [ -f $CPANM ]; then
		for module in $PERL_MODULES; do
			cmd="$PERL -M${module} -e 1"
			$cmd $LOG_CMD > /dev/null 2>&1
			if [ $? != 0 ]; then
				cmd="$CPANM install $module"
				run_cmd "$cmd $LOG_CMD"
				echo "Perl module '$module' successfully installed"
			else
				echo "Perl module '$module' already installed skipping"
			fi
		done
	else
		echo "Perl-$PERL_VERSION has not built 'cpan' tool correctly !!!"
		exit 1
	fi
}

if [ -d $INSTALL ]; then
	echo "ERROR: Perl installation '$INSTALL' already exist"
	echo "Skipping perl-$PERL_VERSION installation"
	install_cpan
	install_modules
else
	echo "Installing perl-$PERL_VERSION"
	init
	get_src
	build_install
	install_cpan
	install_modules
fi

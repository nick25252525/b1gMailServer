#!/bin/sh
#
# Makeself version 2.1.x
#  by Stephane Peter <megastep@megastep.org>
#
# $Id: makeself.sh,v 1.1 2008/06/06 10:02:59 patrick Exp $
#
# Utility to create self-extracting tar.gz archives.
# The resulting archive is a file holding the tar.gz archive with
# a small Shell script stub that uncompresses the archive to a temporary
# directory and then executes a given script from withing that directory.
#
# Makeself home page: http://www.megastep.org/makeself/
#
# Version 2.0 is a rewrite of version 1.0 to make the code easier to read and maintain.
#
# Version history :
# - 1.0 : Initial public release
# - 1.1 : The archive can be passed parameters that will be passed on to
#         the embedded script, thanks to John C. Quillan
# - 1.2 : Package distribution, bzip2 compression, more command line options,
#         support for non-temporary archives. Ideas thanks to Francois Petitjean
# - 1.3 : More patches from Bjarni R. Einarsson and Francois Petitjean:
#         Support for no compression (--nocomp), script is no longer mandatory,
#         automatic launch in an xterm, optional verbose output, and -target 
#         archive option to indicate where to extract the files.
# - 1.4 : Improved UNIX compatibility (Francois Petitjean)
#         Automatic integrity checking, support of LSM files (Francois Petitjean)
# - 1.5 : Many bugfixes. Optionally disable xterm spawning.
# - 1.5.1 : More bugfixes, added archive options -list and -check.
# - 1.5.2 : Cosmetic changes to inform the user of what's going on with big 
#           archives (Quake III demo)
# - 1.5.3 : Check for validity of the DISPLAY variable before launching an xterm.
#           More verbosity in xterms and check for embedded command's return value.
#           Bugfix for Debian 2.0 systems that have a different "print" command.
# - 1.5.4 : Many bugfixes. Print out a message if the extraction failed.
# - 1.5.5 : More bugfixes. Added support for SETUP_NOCHECK environment variable to
#           bypass checksum verification of archives.
# - 1.6.0 : Compute MD5 checksums with the md5sum command (patch from Ryan Gordon)
# - 2.0   : Brand new rewrite, cleaner architecture, separated header and UNIX ports.
# - 2.0.1 : Added --copy
# - 2.1.0 : Allow multiple tarballs to be stored in one archive, and incremental updates.
#           Added --nochown for archives
#           Stopped doing redundant checksums when not necesary
# - 2.1.1 : Work around insane behavior from certain Linux distros with no 'uncompress' command
#           Cleaned up the code to handle error codes from compress. Simplified the extraction code.
# - 2.1.2 : Some bug fixes. Use head -n to avoid problems.
# - 2.1.3 : Bug fixes with command line when spawning terminals.
#           Added --tar for archives, allowing to give arbitrary arguments to tar on the contents of the archive.
#           Added --noexec to prevent execution of embedded scripts.
#           Added --nomd5 and --nocrc to avoid creating checksums in archives.
#           Added command used to create the archive in --info output.
#           Run the embedded script through eval.
# - 2.1.4 : Fixed --info output.
#           Generate random directory name when extracting files to . to avoid problems. (Jason Trent)
#           Better handling of errors with wrong permissions for the directory containing the files. (Jason Trent)
#           Avoid some race conditions (Ludwig Nussel)
#           Unset the $CDPATH variable to avoid problems if it is set. (Debian)
#           Better handling of dot files in the archive directory.
#
# (C) 1998-2005 by St�phane Peter <megastep@megastep.org>
#
# This software is released under the terms of the GNU GPL version 2 and above
# Please read the license at http://www.gnu.org/copyleft/gpl.html
#

MS_VERSION=2.1.4
MS_COMMAND="$0"
unset CDPATH

for f in "${1+"$@"}"; do
    MS_COMMAND="$MS_COMMAND \\\\
    \\\"$f\\\""
done

# Procedures

MS_Usage()
{
    echo "Usage: $0 [params] archive_dir file_name label [startup_script] [args]"
    echo "params can be one or more of the following :"
    echo "    --version | -v  : Print out Makeself version number and exit"
    echo "    --help | -h     : Print out this help message"
    echo "    --gzip          : Compress using gzip (default if detected)"
    echo "    --bzip2         : Compress using bzip2 instead of gzip"
    echo "    --compress      : Compress using the UNIX 'compress' command"
    echo "    --nocomp        : Do not compress the data"
    echo "    --notemp        : The archive will create archive_dir in the"
    echo "                      current directory and uncompress in ./archive_dir"
    echo "    --copy          : Upon extraction, the archive will first copy itself to"
    echo "                      a temporary directory"
    echo "    --append        : Append more files to an existing Makeself archive"
    echo "                      The label and startup scripts will then be ignored"
    echo "    --current       : Files will be extracted to the current directory."
    echo "                      Implies --notemp."
    echo "    --nomd5         : Don't calculate an MD5 for archive"
    echo "    --nocrc         : Don't calculate a CRC for archive"
    echo "    --header file   : Specify location of the header script"
    echo "    --follow        : Follow the symlinks in the archive"
    echo "    --nox11         : Disable automatic spawn of a xterm"
    echo "    --nowait        : Do not wait for user input after executing embedded"
    echo "                      program from an xterm"
    echo "    --lsm file      : LSM file describing the package"
    echo
    echo "Do not forget to give a fully qualified startup script name"
    echo "(i.e. with a ./ prefix if inside the archive)."
    exit 1
}

# Default settings
if type gzip 2>&1 > /dev/null; then
    COMPRESS=gzip
else
    COMPRESS=Unix
fi
KEEP=n
CURRENT=n
NOX11=n
APPEND=n
COPY=none
TAR_ARGS=cvf
HEADER=`dirname $0`/makeself-header.sh

# LSM file stuff
LSM_CMD="echo No LSM. >> \"\$archname\""

while true
do
    case "$1" in
    --version | -v)
	echo Makeself version $MS_VERSION
	exit 0
	;;
    --bzip2)
	COMPRESS=bzip2
	shift
	;;
    --gzip)
	COMPRESS=gzip
	shift
	;;
    --compress)
	COMPRESS=Unix
	shift
	;;
    --nocomp)
	COMPRESS=none
	shift
	;;
    --notemp)
	KEEP=y
	shift
	;;
    --copy)
	COPY=copy
	shift
	;;
    --current)
	CURRENT=y
	KEEP=y
	shift
	;;
    --header)
	HEADER="$2"
	shift 2
	;;
    --follow)
	TAR_ARGS=cvfh
	shift
	;;
    --nox11)
	NOX11=y
	shift
	;;
    --nowait)
	shift
	;;
    --nomd5)
	NOMD5=y
	shift
	;;
    --nocrc)
	NOCRC=y
	shift
	;;
    --append)
	APPEND=y
	shift
	;;
    --lsm)
	LSM_CMD="cat \"$2\" >> \"\$archname\""
	shift 2
	;;
    -h | --help)
	MS_Usage
	;;
    -*)
	echo Unrecognized flag : "$1"
	MS_Usage
	;;
    *)
	break
	;;
    esac
done

archdir="$1"
archname="$2"

if test "$APPEND" = y; then
    if test $# -lt 2; then
	MS_Usage
    fi

    # Gather the info from the original archive
    OLDENV=`sh "$archname" --dumpconf`
    if test $? -ne 0; then
	echo "Unable to update archive: $archname" >&2
	exit 1
    else
	eval "$OLDENV"
    fi
else
    if test "$KEEP" = n -a $# = 3; then
	echo "ERROR: Making a temporary archive with no embedded command does not make sense!" >&2
	echo
	MS_Usage
    fi
    # We don't really want to create an absolute directory...
    if test "$CURRENT" = y; then
	archdirname="."
    else
	archdirname=`basename "$1"`
    fi

    if test $# -lt 3; then
	MS_Usage
    fi

    LABEL="$3"
    SCRIPT="$4"
    test x$SCRIPT = x || shift 1
    shift 3
    SCRIPTARGS="$*"
fi

if test "$KEEP" = n -a "$CURRENT" = y; then
    echo "ERROR: It is A VERY DANGEROUS IDEA to try to combine --notemp and --current." >&2
    exit 1
fi

case $COMPRESS in
gzip)
    GZIP_CMD="gzip -c9"
    GUNZIP_CMD="gzip -cd"
    ;;
bzip2)
    GZIP_CMD="bzip2 -9"
    GUNZIP_CMD="bzip2 -d"
    ;;
Unix)
    GZIP_CMD="compress -cf"
    GUNZIP_CMD="exec 2>&-; uncompress -c || test \\\$? -eq 2 || gzip -cd"
    ;;
none)
    GZIP_CMD="cat"
    GUNZIP_CMD="cat"
    ;;
esac

tmpfile="${TMPDIR:=/tmp}/mkself$$"

if test -f $HEADER; then
	oldarchname="$archname"
	archname="$tmpfile"
	# Generate a fake header to count its lines
	SKIP=0
    . $HEADER
    SKIP=`cat "$tmpfile" |wc -l`
	# Get rid of any spaces
	SKIP=`expr $SKIP`
	rm -f "$tmpfile"
    echo Header is $SKIP lines long >&2

	archname="$oldarchname"
else
    echo "Unable to open header file: $HEADER" >&2
    exit 1
fi

echo

if test "$APPEND" = n; then
    if test -f "$archname"; then
		echo "WARNING: Overwriting existing file: $archname" >&2
    fi
fi

USIZE=`du -ks $archdir | cut -f1`
DATE=`LC_ALL=C date`

if test "." = "$archdirname"; then
	if test "$KEEP" = n; then
		archdirname="makeself-$$-`date +%Y%m%d%H%M%S`"
	fi
fi

test -d "$archdir" || { echo "Error: $archdir does not exist."; rm -f "$tmpfile"; exit 1; }
echo About to compress $USIZE KB of data...
echo Adding files to archive named \"$archname\"...
(cd "$archdir" && ( tar $TAR_ARGS - . | eval "$GZIP_CMD" ) >> "$tmpfile") || { echo Aborting: Archive directory not found or temporary file: "$tmpfile" could not be created.; rm -f "$tmpfile"; exit 1; }
echo >> "$tmpfile" >&- # try to close the archive

fsize=`cat "$tmpfile" | wc -c | tr -d " "`

# Compute the checksums

md5sum=00000000000000000000000000000000
crcsum=0000000000

if test "$NOCRC" = y; then
	echo "skipping crc at user request"
else
	crcsum=`cat "$tmpfile" | CMD_ENV=xpg4 cksum | sed -e 's/ /Z/' -e 's/	/Z/' | cut -dZ -f1`
	echo "CRC: $crcsum"
fi

# Try to locate a MD5 binary
OLD_PATH=$PATH
PATH=${GUESS_MD5_PATH:-"$OLD_PATH:/bin:/usr/bin:/sbin:/usr/local/ssl/bin:/usr/local/bin:/opt/openssl/bin"}
MD5_PATH=`type -p md5sum`
MD5_PATH=${MD5_PATH:-`type -p md5`}
PATH=$OLD_PATH

if test "$NOMD5" = y; then
	echo "skipping md5sum at user request"
else
	if test -x "$MD5_PATH"; then
		md5sum=`cat "$tmpfile" | "$MD5_PATH" | cut -b-32`;
		echo "MD5: $md5sum"
	else
		echo "MD5: none, md5sum binary not found"
	fi
fi

if test "$APPEND" = y; then
    mv "$archname" "$archname".bak || exit

    # Prepare entry for new archive
    filesizes="$filesizes $fsize"
    CRCsum="$CRCsum $crcsum"
    MD5sum="$MD5sum $md5sum"
    USIZE=`expr $USIZE + $OLDUSIZE`
    # Generate the header
    . $HEADER
    # Append the original data
    tail -n +$OLDSKIP "$archname".bak >> "$archname"
    # Append the new data
    cat "$tmpfile" >> "$archname"

    chmod +x "$archname"
    rm -f "$archname".bak
    echo Self-extractible archive \"$archname\" successfully updated.
else
    filesizes="$fsize"
    CRCsum="$crcsum"
    MD5sum="$md5sum"

    # Generate the header
    . $HEADER

    # Append the compressed tar data after the stub
    echo
    cat "$tmpfile" >> "$archname"
    chmod +x "$archname"
    echo Self-extractible archive \"$archname\" successfully created.
fi
rm -f "$tmpfile"

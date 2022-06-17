#!/bin/sh

#
# SPDX-License-Identifier: BSD-2-Clause-FreeBSD
#
# Copyright (c) 2020 Peter Holm <pho@FreeBSD.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# Variation of sendfile21.sh. Short read seen.

. ../default.cfg
[ `id -u` -ne 0 ] && echo "Must be root!" && exit 1

dir=/tmp
odir=`pwd`
cd $dir
sed '1,/^EOF/d' < $odir/$0 > $dir/sendfile23.c
mycc -o sendfile23 -Wall -Wextra -O0 -g sendfile23.c || exit 1
rm -f sendfile23.c
cd $odir

set -e
mount | grep "on $mntpoint " | grep -q /dev/md && umount -f $mntpoint
[ -c /dev/md$mdstart ] &&  mdconfig -d -u $mdstart
mdconfig -a -t swap -s 1g -u $mdstart
newfs $newfs_flags -n md$mdstart > /dev/null
mount /dev/md$mdstart $mntpoint
set +e

cd $mntpoint
dd if=/dev/random of=input bs=4k count=100 status=none

(cd $odir/../testcases/swap; ./swap -t 5m -i 20 -l 100 > /dev/null) &
sleep 30
n=1
start=` date +%s`
while [ $((` date +%s` - start)) -lt 180 ]; do
	rm -f output
#	The umount is needed to trigger the short read error
	umount $mntpoint 2>/dev/null # busy umount
	$dir/sendfile23
	s=$?
	cmp -s input output || break
	[ `stat -f '%z' input` -ne ` stat -f '%z' output` ] && break
	n=$((n + 1))
done
while pgrep -q swap; do
	pkill swap
done
cmp -s input output || { echo "Loop #$n"; ls -l; s=1; }
wait
[ -f sendfile23.core -a $s -eq 0 ] &&
    { ls -l sendfile23.core; mv sendfile23.core $dir; s=1; }
cd $odir

for i in `jot 6`; do
	mount | grep -q "on $mntpoint " || break
	umount $mntpoint && break || sleep 10
	[ $i -eq 6 ] &&
	    { echo FATAL; fstat -mf $mntpoint; exit 1; }
done
mdconfig -d -u $mdstart
rm -rf $dir/sendfile23
exit $s

EOF
#include <sys/param.h>
#include <sys/fcntl.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <sys/wait.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define DEBUG 1

static void
test(void)
{
	struct stat st;
	off_t rd, written, pos;
	pid_t pid;
	int error, from, n, status, sv[2], to;
	char buf[4086];
	const char *from_name, *to_name;

	from_name = "input";
	to_name = "output";

	if ((error = socketpair(AF_UNIX, SOCK_STREAM, 0, sv)) == -1)
		err(1, "socketpair");

	if ((from = open(from_name, O_RDONLY)) == -1)
		err(1, "open read %s", from_name);

	if ((error = fstat(from, &st)) == -1)
		err(1, "stat %s", from_name);

	pid = fork();
	if (pid == -1)
		err(1, "fork");
	else if (pid != 0) {
		setproctitle("parent");
		close(sv[1]);

		pos = 0;
		for (;;) {
			error = sendfile(from, sv[0], pos, st.st_size - pos,
			    NULL, &written, 0);
			if (error == -1)
				err(1, "sendfile");
			if (written != st.st_size)
				fprintf(stderr, "sendfile sent %d bytes\n",
				    (int)written);
			pos += written;
			if (pos == st.st_size)
				break;
		}
		close(sv[0]);
		if (pos != st.st_size)
			fprintf(stderr, "%d written, expected %d\n",
			   (int) pos, (int)st.st_size);
		if (waitpid(pid, &status, 0) != pid)
			err(1, "waitpid(%d)", pid);
		_exit(WEXITSTATUS(status));
	} else {
		setproctitle("child");
		close(from);
		close(sv[0]);

		if ((to = open(to_name, O_RDWR | O_CREAT, DEFFILEMODE)) ==
		    -1)
			err(1, "open write %s", to_name);

		rd = 0;
		for (;;) {
			n = read(sv[1], buf, sizeof(buf));
			if (n == -1)
				err(1, "read");
			else if (n == 0)
				break;
			rd += n;
			if (write(to, buf, n) != n)
				err(1, "write()");
		}
		close(to);
		close(sv[1]);
		if (rd != st.st_size)
			fprintf(stderr, "Short read %d, expected %d\n",
			    (int)rd, (int)st.st_size);
		_exit(0);
	}
	_exit(0);
}

int
main(void)
{
	pid_t pid;
	int e, status;

	e = 0;
	if ((pid = fork()) == 0)
		test();
	if (pid == -1)
		err(1, "fork()");
	if (waitpid(pid, &status, 0) == -1)
		err(1, "waitpid(%d)", pid);
	if (status != 0) {
		if (WIFSIGNALED(status))
			fprintf(stderr,
			    "pid %d exit signal %d\n",
			    pid, WTERMSIG(status));
	}
	e += status == 0 ? 0 : 1;

	return (e);
}

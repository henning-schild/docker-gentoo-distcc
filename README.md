# Gentoo Docker image with distcc

[![Docker Pulls](https://img.shields.io/docker/pulls/ksmanis/gentoo-distcc?label=pulls&logo=docker)](https://hub.docker.com/r/ksmanis/gentoo-distcc)
[![build](https://github.com/KSmanis/docker-gentoo-distcc/actions/workflows/build.yml/badge.svg)](https://github.com/KSmanis/docker-gentoo-distcc/actions/workflows/build.yml)
[![lint](https://github.com/KSmanis/docker-gentoo-distcc/actions/workflows/lint.yml/badge.svg)](https://github.com/KSmanis/docker-gentoo-distcc/actions/workflows/lint.yml)
[![pre-commit enabled](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg?logo=renovatebot&logoColor=white)](https://renovatebot.com/)
[![Conventional Commits](https://img.shields.io/badge/Conventional%20Commits-1.0.0-yellow.svg)](https://conventionalcommits.org)

Decrease Gentoo compilation times by leveraging spare resources, such as an
Ubuntu or Windows box idling around. Docker is the only prerequisite.

## Features

- Flexible deployment
  - Locally (in a private network)
  - Remotely (over the internet)
- Out-of-the-box support for the following Gentoo architectures:
  - `amd64`
  - `arm`
  - `arm64`
  - `ppc64`
  - `x86`

*Note*: Only the stable toolchain of these architectures is currently supported.

## Usage

distcc can run over TCP or SSH connections. TCP connections are fast but
relatively insecure, whereas SSH connections are secure but slower. In a trusted
environment, such as a LAN, you should use TCP connections for efficiency;
otherwise use SSH connections.

### TCP

On the worker node(s), run the containerized distcc server (distccd):

```shell
docker run -d -p 3632:3632 --name gentoo-distcc-tcp --rm ksmanis/gentoo-distcc:tcp
```

distccd should now be accessible from all interfaces at port 3632
(`0.0.0.0:3632`):

```shell
$ docker ps
CONTAINER ID        IMAGE                       COMMAND                  CREATED             STATUS              PORTS                    NAMES
405bb6e87ce8        ksmanis/gentoo-distcc:tcp   "tini -e 143 -- dock…"   2 seconds ago       Up 2 seconds        0.0.0.0:3632->3632/tcp   gentoo-distcc-tcp
```

Command-line arguments are passed on verbatim to distccd. For instance, you can
turn on the built-in HTTP statistics server:

```shell
docker run -d -p 3632-3633:3632-3633 --name gentoo-distcc-tcp --rm ksmanis/gentoo-distcc:tcp --stats
```

The statistics server should now be accessible from all interfaces at port 3633
(`0.0.0.0:3633`):

```shell
$ docker ps
CONTAINER ID        IMAGE                       COMMAND                  CREATED             STATUS              PORTS                              NAMES
4e553e359782        ksmanis/gentoo-distcc:tcp   "tini -e 143 -- dock…"   3 seconds ago       Up 2 seconds        0.0.0.0:3632-3633->3632-3633/tcp   gentoo-distcc-tcp
```

For a full list of options refer to
[distccd(1)](https://linux.die.net/man/1/distccd).

### SSH

On the worker node(s), run the containerized SSH server (sshd):

```shell
docker run -d -p 30022:22 -e AUTHORIZED_KEYS="..." --name gentoo-distcc-ssh --rm ksmanis/gentoo-distcc:ssh
```

sshd should now be accessible from all interfaces at port 30022
(`0.0.0.0:30022`):

```shell
$ docker ps
CONTAINER ID        IMAGE                       COMMAND                  CREATED             STATUS              PORTS                   NAMES
5aa87c1eaf59        ksmanis/gentoo-distcc:ssh   "docker-entrypoint.sh"   3 seconds ago       Up 2 seconds        0.0.0.0:30022->22/tcp   gentoo-distcc-ssh
```

Instead of including the public key verbatim in the above command, you may
prefer to read it from a file on the Docker host:

```shell
docker run -d -p 30022:22 -e AUTHORIZED_KEYS="$(cat /path/to/key.pub)" --name gentoo-distcc-ssh --rm ksmanis/gentoo-distcc:ssh
```

Command-line arguments are passed on verbatim to sshd. For a full list of
options refer to [sshd(8)](https://linux.die.net/man/8/sshd).

#### Security

The SSH server allows only public key authentication. More specifically, only
the `distcc-ssh` user is accessible with the public key provided with the
required `AUTHORIZED_KEYS` environment variable. The username is configurable
through the optional `SSH_USERNAME` environment variable:

```shell
docker run -d -p 30022:22 -e SSH_USERNAME=bob -e AUTHORIZED_KEYS="..." --name gentoo-distcc-ssh --rm ksmanis/gentoo-distcc:ssh
```

### Persistent [ccache(1)](https://ccache.dev/manual/latest.html)

Ccache speeds up recompilation by caching the result of previous compilations
and detecting when the same compilation is being done again. That can help save
time on compilation if you end up recompiling for any reason i.e. because you
have multiple gentoo machines which have an overlapping package selection.

Check the [gentoo wiki](https://wiki.gentoo.org/wiki/Ccache) to learn more. If
you only have one gentoo machine and it has enough disk space to host its own
cache, you might be better off with one local ccache on that machine with
`FEATURES="ccache"`.

To use ccache with the container images just mount a ccache folder into the
container as `/var/cache/ccache`.

Create a new ccache folder:

```shell
cd $HOME
mkdir gentoo-distcc-ccache
cat << EOF > gentoo-distcc-ccache/ccache.conf
max_size = 10.0G
hash_dir = false
compiler_check = %compiler% -v
EOF
# as root chown to 240:240 (uid:gid of distcc on gentoo)
su -c "chown -R 240:240 gentoo-distcc-ccache"
```

Now simply add `-v $HOME/gentoo-distcc-ccache/:/var/cache/ccache/:rw` to your
`docker run` arguments. i.e.

```shell
docker run -d -p 3632:3632 --name gentoo-distcc-tcp --rm -v $HOME/gentoo-distcc-ccache/:/var/cache/ccache/:rw ksmanis/gentoo-distcc:tcp
```

To check the status of the cache you can run `ccache -s` with the container
image like that:

```shell
docker run --rm -v $HOME/gentoo-distcc-ccache/:/var/cache/ccache/:rw -e CCACHE_DIR=/var/cache/ccache ksmanis/gentoo-distcc:tcp ccache -s
```

A much faster way would be to have ccache also installed on the container host
and get the same information with:

```shell
CCACHE_DIR=$HOME/gentoo-distcc-ccache/ ccache -s
```

You should see the cache filling up and if you compile the same package twice
you should see cache hits coming in. If you are using `FEATURES="ccache"` from
gentoo you might want to disable it for a test. Otherwise local cache hits will
prevent remote compilation.

The cache is a shared folder between the host and the container. If both want to
access it you might have to play with `chown` and `CCACHE_UMASK` (or `umask` in
ccache.conf). Note that a world writable cache will have security implications
on all systems using distcc.

## Testing

A manual way to test the containers is to compile a sample C file:

```c
#include <stdio.h>

int main() {
    printf("Hello, distcc!\n");
    return 0;
}
```

### TCP

```shell
DISTCC_HOSTS="127.0.0.1:3632" DISTCC_VERBOSE=1 distcc gcc -c main.c -o /dev/null
```

### SSH

```shell
DISTCC_HOSTS="@localhost-distcc" DISTCC_VERBOSE=1 distcc gcc -c main.c -o /dev/null
```

The `localhost-distcc` host should be properly set up in your `~/.ssh/config`:

```ssh-config
Host localhost-distcc
    HostName 127.0.0.1
    Port 30022
    User distcc-ssh
    IdentityFile ~/.ssh/distcc
    StrictHostKeyChecking no
```

*Note*: `StrictHostKeyChecking no` is required in the above configuration
because the host keys of the container are automatically regenerated upon
execution, if missing. If you wish to eliminate this potential security issue,
you should store the host keys in a volume and mount them upon execution so that
they are not regenerated.

#!/bin/sh
# Script function and purpose: archive the Zig dependencies already fetched into
# the three zig-pkg directories so a later build can run with no network access.
#
# This is a convenience for offline and air-gapped builds only. It is NOT how
# the FreeBSD port obtains its dependencies: ports/Makefile lists every one in
# ZIG_TUPLE and the ports framework fetches them as ordinary distfiles, so
# vendor.tar.zst is neither required nor tracked.
#
# Run a normal online build first, which populates the directories, then run
# this from the project root. Restore with:
#
#     tar --zstd -xf vendor.tar.zst
#
tar --zstd -cvf vendor.tar.zst zig-pkg sakura-ui/zig-pkg sakura-core/zig-pkg

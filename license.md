BSD 2-Clause License

Copyright (c) 2026 orpheus497

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

---

## Third-party components

Sakura is a fork of Ly (https://codeberg.org/fairyglade/ly), which is released
under the WTFPL. The WTFPL permits redistribution under any terms, so the
inherited work is re-released here under the BSD 2-Clause License above.

`res/setup.sh` is **not** covered by the BSD 2-Clause License above. Its header
releases it under the WTFPL (https://www.wtfpl.net/txt/copying/) and retains
three copyrights, all of which stand: Oswald Buddenhagen (extracted from
kde-workspace, `kdm/kfrontend/genkdmconf.c`), Pier Luigi Fiorini, and The Fairy
Glade.

Bundled dependencies remain under their own licenses: zig-clap, ziglua,
LuaJIT, termbox2, zigini, ini, translate_c and aro are MIT; libxcb is MIT;
OpenPAM is BSD.

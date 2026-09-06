#!/usr/bin/env python3
"""Execute real host constructors with mocked IPC/open; never access devices."""
import os
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    tmp = Path(directory)
    stub = tmp / 'boost/interprocess/sync/named_mutex.hpp'
    stub.parent.mkdir(parents=True)
    stub.write_text(r'''
#pragma once
#include <string>
#include <vector>
inline std::vector<std::string> mutexes, removed;
namespace boost { namespace interprocess {
struct open_or_create_t {};
inline open_or_create_t open_or_create;
class named_mutex {
public:
 named_mutex(open_or_create_t, const char *name) { mutexes.emplace_back(name); }
 static bool remove(const char *name) { removed.emplace_back(name); return true; }
 void lock() {} void unlock() {}
};
}}
''')
    (tmp / 'test.cpp').write_text(r'''
#include <coyote/cThread.hpp>
#include <coyote/cRcnfg.hpp>
#include <coyote/cResidentServiceControl.hpp>
#include <cassert>
#include <cerrno>
#include <iostream>
std::vector<std::string> opened;
bool allow_open=false;
extern "C" int __wrap_open(const char *path, int flags, ...) {
 opened.emplace_back(path); errno=ENOENT; return allow_open ? 123 : -1;
}
extern "C" int __wrap_close(int fd) { assert(fd==123); return 0; }
template<class F> void fails(F f) {
 bool failed=false; try { f(); } catch(const std::exception&) { failed=true; }
 assert(failed);
}
void constructAll() {
 fails([]{ coyote::cThread t(3,getpid(),7); });
 fails([]{ coyote::cRcnfg r(7); });
 fails([]{ coyote::cResidentServiceControl s(7); });
}
int main() {
 for(const char *prefix : {"coyote_fpga", "coyote_ultrascale_plus_fpga", "coyote_versal_fpga"}) {
  setenv("COYOTE_DEVICE_PREFIX",prefix,1);
  mutexes.clear(); opened.clear(); constructAll();
  std::string p=prefix;
  assert((opened==std::vector<std::string>{"/dev/"+p+"_7_v3", "/dev/"+p+"_7_reconfig", "/dev/"+p+"_7_reconfig"}));
  std::string m=p=="coyote_fpga" ? "" : p+"_";
  assert((mutexes==std::vector<std::string>{m+"mutex_dev_7_vfpa_3",m+"reconfig_mtx"}));
 }
 unsetenv("COYOTE_DEVICE_PREFIX"); opened.clear(); mutexes.clear(); constructAll();
 assert(opened.front()=="/dev/coyote_fpga_7_v3");
 assert(mutexes.front()=="mutex_dev_7_vfpa_3");
 for(const std::string bad : {std::string(""),std::string("../coyote_fpga"),std::string("/dev/coyote_fpga"),std::string("a b"),std::string("a-b"),std::string(65,'x')}) {
  setenv("COYOTE_DEVICE_PREFIX",bad.c_str(),1); opened.clear(); mutexes.clear();
  constructAll(); assert(opened.empty() && mutexes.empty());
 }
 setenv("COYOTE_DEVICE_PREFIX","coyote_versal_fpga",1);
 coyote::cDeviceNamespace snapshot;
 removed.clear(); allow_open=true;
 { coyote::cRcnfg r(7); setenv("COYOTE_DEVICE_PREFIX","coyote_fpga",1); }
 assert(removed.empty()); // Must not unlink a legacy or still-used explicit mutex.
 assert(snapshot.regionPath(0,0)=="/dev/coyote_versal_fpga_0_v0");
 { coyote::cRcnfg r(7); }
 assert((removed==std::vector<std::string>{"reconfig_mtx"}));
 std::cout<<"PASS: three real APIs, all family/default paths and mutex identities, fail-closed invalid prefix, no fallback, stable destructor namespace\n";
}
''')
    command = [os.environ.get('CXX', 'c++'), '-std=c++17', '-O1', '-pthread',
               '-fsanitize=address,undefined', '-fno-omit-frame-pointer',
               '-I'+str(tmp), '-I'+str(root/'sw/include'),
               str(tmp/'test.cpp')]
    command += [str(root/'sw/src'/name) for name in
                ['cThread.cpp','cRcnfg.cpp','cResidentServiceControl.cpp']]
    command += ['-Wl,--wrap=open', '-Wl,--wrap=close', '-o', str(tmp/'test')]
    subprocess.run(command, check=True)
    subprocess.run([str(tmp/'test')], check=True, timeout=30)

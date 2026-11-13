/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Sends a message through every vFPGA at once and checks that each one echoes it
// back unchanged. Exits with failure if any vFPGA returns different data.

#include <cstdlib>
#include <cstring>
#include <iostream>
#include <memory>
#include <vector>

// External library, Boost, for easier parsing of CLI arguments
#include <boost/program_options.hpp>

// Coyote-specific includes
#include <coyote/cBench.hpp>
#include <coyote/cThread.hpp>

int main(int argc, char *argv[]) {
    unsigned int n_vfpga, message_size;

    boost::program_options::options_description runtime_options("Coyote many-vFPGA loopback options");
    runtime_options.add_options()
        ("n_vfpga,n", boost::program_options::value<unsigned int>(&n_vfpga)->default_value(32), "Number of vFPGAs to test, from vFPGA 0 upwards")
        ("message_size,s", boost::program_options::value<unsigned int>(&message_size)->default_value(64 * 1024), "Bytes sent through each vFPGA");
    boost::program_options::variables_map command_line_arguments;
    boost::program_options::store(boost::program_options::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    boost::program_options::notify(command_line_arguments);

    HEADER("CLI PARAMETERS:");
    std::cout << "Number of Coyote vFPGAs: " << n_vfpga << std::endl;
    std::cout << "Message size: " << message_size << std::endl;

    std::vector<std::unique_ptr<coyote::cThread>> coyote_threads;
    std::vector<char *> src_mems, dst_mems;
    for (unsigned int i = 0; i < n_vfpga; i++) {
        // One Coyote thread per vFPGA, with its own source and destination buffers
        coyote_threads.emplace_back(new coyote::cThread(i, getpid()));
        src_mems.emplace_back((char *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, message_size}));
        dst_mems.emplace_back((char *) coyote_threads[i]->getMem({coyote::CoyoteAllocType::HPF, message_size}));
        if (!src_mems[i] || !dst_mems[i]) {
            std::cerr << "Could not allocate memory for vFPGA " << i << ", exiting..." << std::endl;
            return EXIT_FAILURE;
        }

        // A different pattern per vFPGA, so data routed to the wrong vFPGA is caught
        for (unsigned int k = 0; k < message_size; k++) {
            src_mems[i][k] = (char) ((k + 31 * i) & 0xff);
        }
        memset(dst_mems[i], 0, message_size);
        coyote_threads[i]->clearCompleted();
    }

    // Start all transfers before waiting on any, so the vFPGAs run in parallel
    // LOCAL_TRANSFER: CPU memory => vFPGA (loopback) => CPU memory
    for (unsigned int i = 0; i < n_vfpga; i++) {
        coyote::localSg src_sg = { .addr = src_mems[i], .len = message_size };
        coyote::localSg dst_sg = { .addr = dst_mems[i], .len = message_size };
        coyote_threads[i]->invoke(coyote::CoyoteOper::LOCAL_TRANSFER, src_sg, dst_sg);
    }
    for (unsigned int i = 0; i < n_vfpga; i++) {
        while (coyote_threads[i]->checkCompleted(coyote::CoyoteOper::LOCAL_TRANSFER) != 1) {}
    }

    unsigned int failed = 0;
    for (unsigned int i = 0; i < n_vfpga; i++) {
        bool ok = memcmp(src_mems[i], dst_mems[i], message_size) == 0;
        std::cout << "vFPGA " << i << ": " << (ok ? "echo correct" : "echo WRONG") << std::endl;
        failed += ok ? 0 : 1;
    }

    if (failed > 0) {
        std::cerr << failed << " of " << n_vfpga << " vFPGAs returned wrong data" << std::endl;
        return EXIT_FAILURE;
    }
    std::cout << "All " << n_vfpga << " vFPGAs echoed their data correctly" << std::endl;
    return EXIT_SUCCESS;
}

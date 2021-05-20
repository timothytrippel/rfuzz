# BSD 3-Clause License
#
# Copyright (c) 2021, Timothy Trippel <trippel@umich.edu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permisson.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

FROM ubuntu:18.04
MAINTAINER trippel@umich.edu
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get upgrade -y && apt-get autoremove -y

# Setup directory structure
ENV SRC=/src
RUN mkdir -p $SRC && chmod a+rwx $SRC

# Install packages
RUN apt-get update && apt-get install -y \
      build-essential \
      meson \
      pkg-config \
      openjdk-8-jdk \
      verilator \
      cargo \
      curl \
      python3-toml \
      python3-numpy \
      python3-matplotlib \
      graphviz

# Install Verilator v4.101
RUN apt-get update && apt-get install -y \
      git \
      autoconf \
      flex \
      bison
RUN cd $SRC && git clone https://github.com/verilator/verilator.git
RUN cd $SRC/verilator && git checkout 7be343fd7c885359ac29e50e9732509caf64637d
RUN cd $SRC/verilator && autoconf
ENV VERILATOR_ROOT=$SRC/verilator
RUN cd $SRC/verilator && ./configure && make -j 4 && make install
RUN apt-get remove --purge -y git autoconf flex bison && apt-get autoremove -y
 
# Install SBT
RUN echo "deb https://dl.bintray.com/sbt/debian /" | tee -a /etc/apt/sources.list.d/sbt.list
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 2EE0EA64E40A89B84B2DF73499E82A75642AC823
RUN apt-get update && apt-get install -y sbt

# Configure MATPLOTLIB to run headless
RUN mkdir -p ~/.config/matplotlib
RUN echo "backend: agg" > ~/.config/matplotlib/matplotlibrc

# Install RFUZZ
RUN apt-get update && apt-get install -y git
RUN cd $SRC && git clone https://github.com/timothytrippel/rfuzz.git
ENV RFUZZ=/src/rfuzz
RUN cd $RFUZZ && git checkout hwfuzz-usenix21
RUN cd $RFUZZ && git submodule update --init

WORKDIR $RFUZZ
CMD ["./run.sh"]

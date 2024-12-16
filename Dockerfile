FROM ubuntu:22.04

# 避免安装过程中的交互
ENV DEBIAN_FRONTEND=noninteractive

RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list && \
    sed -i 's|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list

# 安装必要的包
RUN apt-get update && apt-get install -y \
    ubuntu-desktop \
    xterm \
    firefox \
    dbus-x11 \
    x11-utils \
    x11-apps \
    gcc \
    sudo \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# add user
RUN groupadd -r c3v && useradd -m -g c3v c3v
RUN echo "c3v ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
RUN mkdir -p /npu/npu_install && \
    chown -R c3v:c3v /npu
#WORKDIR /npu

# env prepare
COPY --chown=c3v:c3v ./npu_install/* /npu/npu_install/
#RUN ls /npu && ls /npu/npu_install
RUN bash /npu/npu_install/Anaconda3-2024.10-1-Linux-x86_64.sh -b -p /opt/conda && \
    chown -R c3v:c3v /opt/conda

ENV PATH=/opt/conda/bin:$PATH

# switch to c3v user for conda config
USER c3v
RUN echo '. /opt/conda/etc/profile.d/conda.sh' >> ~/.bashrc && \
#    echo 'conda activate base' >> ~/.bashrc && \
#RUN conda init bash && \
#    conda update -n base -c defaults conda -y && \
    conda create -n npu_6.30.7 python=3.8.10 -y

SHELL ["conda", "run", "-n", "npu_6.30.7", "/bin/bash", "-c"]
RUN cd /npu/npu_install && \
    tar -zxvf Vivante_acuity_toolkit_whl_6.30.7_python3.8.10.tgz && \
    cd acuity-toolkit-whl-6.30.7 && \
    pip install -r requirements.txt && \
    cd bin && \
    pip install acuity-6.30.7-cp38-cp38-manylinux2010_x86_64.whl

ENV CONDA_DEFAULT_ENV=npu_6.30.7

WORKDIR /npu

RUN echo "conda activate npu_6.30.7" >> ~/.bashrc

# entry
CMD ["bash"]

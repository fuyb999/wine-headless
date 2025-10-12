FROM ubuntu:22.04

ENV TZ=Asia/Shanghai

RUN sed -i -E 's/(archive|security).ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list

# 安装必要工具
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    software-properties-common

ADD winehq.key /usr/share/keyrings/winehq-archive.key

# 添加Wine仓库
RUN dpkg --add-architecture i386 && \
    echo 'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/winehq-archive.key] https://mirrors.tuna.tsinghua.edu.cn/wine-builds/ubuntu/ jammy main' > /etc/apt/sources.list.d/winehq.list

RUN apt-get update && \
    apt-get install -y winehq-stable cabextract xvfb sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

#RUN wget https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks -O /usr/local/bin/winetricks && \
#    chmod +x /usr/local/bin/winetricks

ADD winetricks /usr/local/bin/winetricks

# 创建非 root 用户
RUN groupadd -r wineuser && \
    useradd -r -g wineuser -m -d /home/wineuser wineuser && \
    echo 'wineuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# 切换到非 root 用户
USER wineuser

# 设置Wine环境
ENV HOME=/home/wineuser
ENV WINEPREFIX=/home/wineuser/.wine
ENV WINEARCH=win32
ENV WINEDEBUG=-all
ENV WINEDLLOVERRIDES="mscoree,mshtml="

# 初始化Wine
RUN xvfb-run -a wineboot --init && \
    xvfb-run winetricks -q vcrun2019 dotnet48

ADD corefonts /home/wineuser/.cache/winetricks/corefonts
RUN xvfb-run winetricks -q corefonts

RUN xvfb-run -a wine cmd /c "echo 32-bit environment ready"

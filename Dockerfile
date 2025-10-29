FROM ubuntu:22.04

ENV TZ=Asia/Shanghai

# 设置时区和安装时区数据
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN sed -i -E 's/(archive|security).ubuntu.com/mirrors.tuna.tsinghua.edu.cn/g' /etc/apt/sources.list

# 安装必要工具和中文字体
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    software-properties-common \
    locales \
    tzdata \
    fonts-noto-cjk \
    fonts-wqy-microhei \
    fonts-wqy-zenhei \
    fontconfig \
    curl \
    unzip

# 生成中文语言环境
RUN locale-gen zh_CN.UTF-8 && \
    update-locale LANG=zh_CN.UTF-8

ENV LANG=zh_CN.UTF-8
ENV LANGUAGE=zh_CN:zh
ENV LC_ALL=zh_CN.UTF-8

ADD winehq.key /usr/share/keyrings/winehq-archive.key

# 添加Wine仓库
RUN dpkg --add-architecture i386 && \
    echo 'deb [arch=amd64,i386 signed-by=/usr/share/keyrings/winehq-archive.key] https://mirrors.tuna.tsinghua.edu.cn/wine-builds/ubuntu/ jammy main' > /etc/apt/sources.list.d/winehq.list

RUN apt-get update && \
    apt-get install -y winehq-stable cabextract xvfb sudo && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

ADD winetricks /usr/local/bin/winetricks

# 创建非 root 用户
RUN groupadd -r wineuser && \
    useradd -r -g wineuser -m -d /home/wineuser wineuser && \
    echo 'wineuser ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

# ==================== MOUNT 逻辑配置 ====================

# 创建多个挂载点目录
RUN mkdir -p /home/wineuser/mount && \
    mkdir -p /home/wineuser/input && \
    mkdir -p /home/wineuser/output && \
    mkdir -p /home/wineuser/shared && \
    chown -R wineuser:wineuser /home/wineuser

# 设置挂载点权限
RUN chmod 755 /home/wineuser/mount && \
    chmod 755 /home/wineuser/input && \
    chmod 755 /home/wineuser/output && \
    chmod 755 /home/wineuser/shared

# 创建挂载点说明文件
RUN echo "此目录用于挂载外部数据卷" > /home/wineuser/mount/README.txt && \
    echo "输入文件目录" > /home/wineuser/input/README.txt && \
    echo "输出文件目录" > /home/wineuser/output/README.txt && \
    echo "共享数据目录" > /home/wineuser/shared/README.txt && \
    chown -R wineuser:wineuser /home/wineuser

# 切换到非 root 用户
USER wineuser

# 设置Wine环境
ENV HOME=/home/wineuser
ENV WINEPREFIX=/home/wineuser/.wine
ENV WINEARCH=win64
ENV WINEDEBUG=-all
ENV WINEDLLOVERRIDES="mscoree,mshtml="

# 初始化Wine
RUN xvfb-run -a wineboot --init

# ==================== Windows Server 2016 配置 ====================

# 配置为 Windows Server 2016
RUN wineserver -w && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v ProductName /t REG_SZ /d "Microsoft Windows Server 2016" /f && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentVersion /t REG_SZ /d "6.3" /f && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuild /t REG_SZ /d "14393" /f && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CurrentBuildNumber /t REG_SZ /d "14393" /f && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v InstallationType /t REG_SZ /d "Server" /f && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v CSDVersion /t REG_SZ /d "" /f && \
    xvfb-run -a wine reg add "HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion" /v EditionID /t REG_SZ /d "ServerStandard" /f

# 设置服务器特定的注册表项
RUN wineserver -w && \
    xvfb-run -a wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\ProductOptions" /v ProductType /t REG_SZ /d "ServerNT" /f && \
    xvfb-run -a wine reg add "HKLM\\SYSTEM\\CurrentControlSet\\Control\\ServerApplications" /v Server /t REG_DWORD /d 1 /f

# ==================== 中文字体支持配置 ====================

# 使用winetricks安装中文字体支持
RUN xvfb-run winetricks -q cjkfonts

# 手动链接系统字体到Wine（备用方案）
USER root
RUN mkdir -p /home/wineuser/.wine/drive_c/windows/Fonts && \
    # 链接系统中文字体到Wine字体目录 \
    ln -sf /usr/share/fonts/truetype/noto/NotoSansCJK-*.ttc /home/wineuser/.wine/drive_c/windows/Fonts/ 2>/dev/null || true && \
    ln -sf /usr/share/fonts/truetype/wqy/wqy-*.ttf /home/wineuser/.wine/drive_c/windows/Fonts/ 2>/dev/null || true && \
    # 设置字体权限 \
    chown -R wineuser:wineuser /home/wineuser/.wine
USER wineuser

# 配置Wine字体注册表
RUN wineserver -w && \
    xvfb-run -a wine reg add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink" /v "Lucida Sans Unicode" /t REG_SZ /d "wqy-microhei.ttc,wqy-microhei" /f && \
    xvfb-run -a wine reg add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink" /v "Microsoft Sans Serif" /t REG_SZ /d "wqy-microhei.ttc,wqy-microhei" /f && \
    xvfb-run -a wine reg add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\FontLink\\SystemLink" /v "Tahoma" /t REG_SZ /d "wqy-microhei.ttc,wqy-microhei" /f

# 设置系统区域和字体替代
RUN wineserver -w && \
    xvfb-run -a wine reg add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" /v "MS Shell Dlg" /t REG_SZ /d "WenQuanYi Micro Hei" /f && \
    xvfb-run -a wine reg add "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes" /v "MS Shell Dlg 2" /t REG_SZ /d "WenQuanYi Micro Hei" /f

# 设置中文语言环境
RUN wineserver -w && \
    xvfb-run -a wine reg add "HKCU\\Control Panel\\International" /v Locale /t REG_SZ /d "zh_CN" /f && \
    xvfb-run -a wine reg add "HKCU\\Control Panel\\International" /v Language /t REG_SZ /d "zh_CN" /f && \
    xvfb-run -a wine reg add "HKCU\\Control Panel\\Desktop" /v PreferredUILanguages /t REG_MULTI_SZ /d "zh-CN" /f

# ==================== 安装必要的运行时库 ====================

# 方法2: 手动下载并安装 64 位 VC++ 运行库
RUN cd /home/wineuser && \
    wget -O vc_redist.x64.exe https://aka.ms/vs/17/release/vc_redist.x64.exe || \
    wget -O vc_redist.x64.exe https://download.visualstudio.microsoft.com/download/pr/9dffa4d9-7c0e-4321-af76-31c8cc75d409/9C1B3B5A8BD8B2EE5BC39A8AA5E16AA50DBA14A5B1EA92D96875A0DF2D5E5A0D/vc_redist.x64.exe || \
    echo "VC++ 64位下载失败"

# 安装 64 位 VC++ 运行库
RUN if [ -f "/home/wineuser/vc_redist.x64.exe" ]; then \
        echo "正在安装 64 位 VC++ 运行库..." && \
        xvfb-run -a wine64 /home/wineuser/vc_redist.x64.exe /install /quiet /norestart; \
    else \
        echo "跳过 VC++ 运行库安装"; \
    fi

ADD corefonts /home/wineuser/.cache/winetricks/corefonts
RUN xvfb-run -a winetricks -q corefonts

# ==================== 创建挂载点使用示例脚本 ====================

# 创建文件操作示例脚本
RUN echo '@echo off\n\
chcp 65001 > nul\n\
echo =========================================\n\
echo       挂载点文件操作演示\n\
echo =========================================\n\
echo.\n\
echo [挂载点目录结构]\n\
echo Z:\\home\\wineuser\\mount\\    - 主挂载点\n\
echo Z:\\home\\wineuser\\input\\    - 输入文件目录\n\
echo Z:\\home\\wineuser\\output\\   - 输出文件目录\n\
echo Z:\\home\\wineuser\\shared\\   - 共享目录\n\
echo.\n\
echo [创建测试文件]\n\
echo 测试文件创建时间: %date% %time% > Z:\\home\\wineuser\\output\\test_output.txt\n\
echo 这是从Wine创建的文件 >> Z:\\home\\wineuser\\output\\test_output.txt\n\
echo 中文内容测试：你好，世界！ >> Z:\\home\\wineuser\\output\\test_output.txt\n\
echo.\n\
echo [显示创建的文件]\n\
type Z:\\home\\wineuser\\output\\test_output.txt\n\
echo.\n\
echo [列出输出目录文件]\n\
dir Z:\\home\\wineuser\\output\\\n\
echo.\n\
echo =========================================\n\
echo 文件操作完成！\n\
pause\n\
' > /home/wineuser/mount_demo.bat

# 创建文件处理脚本
RUN echo '#!/bin/bash\n\
# 挂载点文件处理脚本\n\
echo "处理挂载点文件..."\n\
\n\
# 检查输入目录\n\
if [ -d "/home/wineuser/input" ]; then\n\
    echo "输入目录文件:"\n\
    ls -la /home/wineuser/input/\n\
fi\n\
\n\
# 处理文件（示例）\n\
echo "从Wine处理文件..."\n\
wine cmd /c "chcp 65001 > nul && echo Processing files from mount points... > Z:\\home\\wineuser\\output\\processing_log.txt"\n\
\n\
echo "处理完成！"\n\
' > /home/wineuser/process_files.sh && \
chmod +x /home/wineuser/process_files.sh

# 创建挂载点验证脚本
RUN echo '#!/bin/bash\n\
echo "==================================="\n\
echo "     挂载点配置验证"\n\
echo "==================================="\n\
echo "\n\
echo "挂载点目录权限:"\n\
ls -ld /home/wineuser/mount\n\
ls -ld /home/wineuser/input\n\
ls -ld /home/wineuser/output\n\
ls -ld /home/wineuser/shared\n\
echo "\n\
echo "挂载点内容:"\n\
ls -la /home/wineuser/mount/\n\
echo "\n\
echo "Wine中的挂载点路径对应:"\n\
echo "Linux: /home/wineuser/mount/ -> Wine: Z:\\\\home\\\\wineuser\\\\mount\\\\"\n\
echo "Linux: /home/wineuser/input/ -> Wine: Z:\\\\home\\\\wineuser\\\\input\\\\"\n\
echo "Linux: /home/wineuser/output/ -> Wine: Z:\\\\home\\\\wineuser\\\\output\\\\"\n\
echo "\n\
echo "验证完成！"\n\
' > /home/wineuser/verify_mounts.sh && \
chmod +x /home/wineuser/verify_mounts.sh

# 设置工作目录到主挂载点
WORKDIR /home/wineuser/mount

# ==================== 最终验证和启动配置 ====================

# 验证配置
#RUN wineserver -w && \
#    xvfb-run -a wine cmd /c "chcp 65001 && echo Windows Server 2016 中文环境与挂载点配置完成！"

# 创建启动脚本
RUN echo '#!/bin/bash\n\
echo "==================================="\n\
echo " Windows Server 2016 模拟环境"\n\
echo "==================================="\n\
echo "系统时区: $(date)"\n\
echo "语言环境: $LANG"\n\
echo "Wine架构: $WINEARCH"\n\
echo "工作目录: $(pwd)"\n\
echo "==================================="\n\
echo "挂载点目录:"\n\
echo "  /home/wineuser/mount/    - 主工作目录"\n\
echo "  /home/wineuser/input/    - 输入文件"\n\
echo "  /home/wineuser/output/   - 输出文件"\n\
echo "  /home/wineuser/shared/   - 共享数据"\n\
echo "==================================="\n\
echo "可用命令:"\n\
echo "  wine /home/wineuser/mount_demo.bat    - 挂载点演示"\n\
echo "  ./home/wineuser/verify_mounts.sh      - 验证挂载点"\n\
echo "  ./home/wineuser/process_files.sh      - 处理文件"\n\
echo "  wine /home/wineuser/verify_server.bat - 验证服务器配置"\n\
echo "  wine cmd                              - 启动Windows命令行"\n\
echo "==================================="\n\
\n\
# 验证挂载点\n\
./home/wineuser/verify_mounts.sh\n\
\n\
/bin/bash\n\
' > /home/wineuser/start.sh && \
chmod +x /home/wineuser/start.sh

CMD ["/home/wineuser/start.sh"]
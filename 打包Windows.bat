@echo off
REM 设置控制台编码为 UTF-8
chcp 65001 >nul 2>&1
title SimpleLive Windows 打包工具
setlocal enabledelayedexpansion

REM 切换到脚本所在目录
cd /d "%~dp0"

REM 切换到 Flutter 项目目录
cd simple_live_app

REM 设置变量
set "VERSION=1.11.2"

REM 获取日期时间（格式：周X YYMDD-HHMMSS）
for /f "tokens=1-4 delims=/ " %%a in ('date /t') do (
    set "WEEKDAY=%%a"
    set "YEAR=%%c"
    set "MONTH=%%b"
    set "DAY=%%a"
)
for /f "tokens=1-3 delims=:." %%a in ('echo %TIME: =0%') do (
    set "HOUR=%%a"
    set "MINUTE=%%b"
    set "SECOND=%%c"
)
set "BUILD_DATE=%DATE:~0,4%%DATE:~5,2%%DATE:~8,2%-%TIME: =0%"
set "BUILD_DATE=!BUILD_DATE::=!"

set "OUTPUT_DIR=..\Release"
set "ZIP_OUTPUT_DIR=..\Release-zip"
set "ZIP_NAME=SimpleLive778-Windows-v%VERSION%-%BUILD_DATE%.zip"

echo.
echo ========================================================
echo           SimpleLive Windows 打包工具 v%VERSION%
echo ========================================================
echo.

REM 检查项目文件
echo [检查] 正在验证项目文件...
if not exist "pubspec.yaml" (
    echo.
    echo [错误] 找不到 pubspec.yaml 文件
    echo        请确保在正确的目录下运行此脚本
    echo.
    pause
    exit /b 1
)
echo [检查] 项目文件验证通过
echo.

REM 创建输出目录
if not exist "%OUTPUT_DIR%" mkdir "%OUTPUT_DIR%"
if not exist "%ZIP_OUTPUT_DIR%" mkdir "%ZIP_OUTPUT_DIR%"

echo ========================================================
echo  步骤 1/4: 清理构建缓存
echo ========================================================
echo.

REM 清除旧版本的缓存文件
echo [清理] 检查旧版缓存文件...
if exist "build_cache\ANGLE.7z" (
    echo [清理] 删除旧版 ANGLE 缓存...
    del /F /Q "build_cache\ANGLE.7z" 2>nul
)
if exist "build_cache\mpv-dev-x86_64-20230924-git-652a1dd.7z" (
    echo [清理] 删除旧版 mpv 缓存...
    del /F /Q "build_cache\mpv-dev-x86_64-20230924-git-652a1dd.7z" 2>nul
)

REM 检查并清理损坏的 mpv 缓存
if exist "build\windows\x64\mpv-dev-*.7z" (
    echo [清理] 清理可能损坏的 mpv 下载缓存...
    del /F /Q "build\windows\x64\mpv-dev-*.7z" 2>nul
)

echo [清理] 清理 build 目录...
if exist "build" rmdir /s /q "build" 2>nul

echo [清理] 执行 flutter clean...
call flutter clean >nul 2>&1
echo [清理] 完成
echo.

echo ========================================================
echo  步骤 2/4: 获取项目依赖
echo ========================================================
echo.
echo [依赖] 正在获取 Flutter 依赖包...
echo [依赖] 这可能需要几分钟，请耐心等待...
echo.

call flutter pub get
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [错误] 获取依赖失败
    echo.
    echo        可能的原因:
    echo        1. 网络连接问题
    echo        2. 依赖版本冲突
    echo        3. Flutter SDK 配置问题
    echo.
    echo        请检查上方的错误信息后重试
    echo.
    pause
    exit /b 1
)
echo.
echo [依赖] 依赖获取完成
echo.

echo ========================================================
echo  步骤 3/4: 构建 Windows 应用
echo ========================================================
echo.
echo [构建] 正在编译 Release 版本...
echo [构建] 首次构建可能需要较长时间，请耐心等待...
echo.

call flutter build windows --release
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [错误] 构建失败
    echo.
    echo        可能的原因:
    echo        1. 代码存在编译错误
    echo        2. mpv 库下载失败或校验失败
    echo        3. Visual Studio 未正确安装
    echo.
    echo        如果是 mpv 校验失败，请尝试:
    echo        删除 build\windows\x64\mpv-dev-*.7z 后重试
    echo.
    pause
    exit /b 1
)
echo.
echo [构建] 编译完成
echo.

echo ========================================================
echo  步骤 4/4: 打包输出文件
echo ========================================================
echo.

echo [打包] 复制文件到 Release 目录...
xcopy /E /I /Y "build\windows\x64\runner\Release\*" "%OUTPUT_DIR%\" >nul 2>&1
if exist "build\windows\x64\runner\Release\data" (
    xcopy /E /I /Y "build\windows\x64\runner\Release\data" "%OUTPUT_DIR%\data\" >nul 2>&1
)

echo [打包] 创建压缩包: %ZIP_NAME%
powershell -NoProfile -ExecutionPolicy Bypass -Command "Compress-Archive -Path '.\%OUTPUT_DIR%\*' -DestinationPath '.\%ZIP_OUTPUT_DIR%\%ZIP_NAME%' -Force" 2>nul

if exist ".\%ZIP_OUTPUT_DIR%\%ZIP_NAME%" (
    echo [打包] 压缩包创建成功
    echo.
    echo ========================================================
    echo                    构建成功!
    echo ========================================================
    echo.
    echo  可执行文件: %CD%\%OUTPUT_DIR%\SimpleLive778.exe
    echo  压缩包位置: %CD%\%ZIP_OUTPUT_DIR%\%ZIP_NAME%
    echo.
    echo ========================================================
) else (
    echo.
    echo [错误] 创建压缩包失败
    echo        请检查磁盘空间和文件权限
)

echo.
echo 按任意键退出...
pause >nul

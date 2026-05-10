# 设置变量
$version = "1.11.2"
$buildDate = Get-Date -Format "yyyyMMdd-HHmmss"
$outputDir = "Release"
$zipOutputDir = "Release-zip"
$zipName = "SimpleLive778-Windows-v$version-$buildDate.zip"

# 创建输出目录
New-Item -ItemType Directory -Force -Path $outputDir
New-Item -ItemType Directory -Force -Path $zipOutputDir

# 清理之前的构建（保留 mpv 库和 ANGLE 缓存）
Write-Host "正在清理之前的构建..."
Remove-Item -Recurse -Force "$outputDir\*" -ErrorAction SilentlyContinue

# 备份缓存文件
$mpvCache = "build\windows\x64\mpv-dev-x86_64-20230924-git-652a1dd.7z"
$angleCache = "build\windows\x64\ANGLE.7z"
$cacheDir = "build_cache"
New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null

if (Test-Path $mpvCache) {
    Write-Host "检测到 mpv 库缓存，正在备份..."
    Copy-Item -Path $mpvCache -Destination $cacheDir -Force
}
if (Test-Path $angleCache) {
    Write-Host "检测到 ANGLE 库缓存，正在备份..."
    Copy-Item -Path $angleCache -Destination $cacheDir -Force
}

flutter clean

# 恢复缓存文件
if (Test-Path "$cacheDir\mpv-dev-x86_64-20230924-git-652a1dd.7z") {
    Write-Host "正在恢复 mpv 库缓存..."
    New-Item -ItemType Directory -Force -Path "build\windows\x64" | Out-Null
    Copy-Item -Path "$cacheDir\mpv-dev-x86_64-20230924-git-652a1dd.7z" -Destination "build\windows\x64\" -Force
}
if (Test-Path "$cacheDir\ANGLE.7z") {
    Write-Host "正在恢复 ANGLE 库缓存..."
    New-Item -ItemType Directory -Force -Path "build\windows\x64" | Out-Null
    Copy-Item -Path "$cacheDir\ANGLE.7z" -Destination "build\windows\x64\" -Force
}

# 获取依赖
Write-Host "正在获取依赖..."
flutter pub get

# 构建 Windows 应用
Write-Host "正在构建 Windows 应用..."
flutter build windows --release

# 复制构建产物到 Release 目录
Write-Host "正在复制文件到 $outputDir..."
$buildDir = "build\windows\x64\runner\Release"
Copy-Item -Path "$buildDir\*" -Destination $outputDir -Recurse -Force

# 复制 data 目录
$dataDir = "build\windows\x64\runner\Release\data"
if (Test-Path $dataDir) {
    Copy-Item -Path $dataDir -Destination $outputDir -Recurse -Force
}

# 创建 ZIP 文件
Write-Host "正在创建 ZIP 文件: $zipName"
Compress-Archive -Path "$outputDir\*" -DestinationPath "$zipOutputDir\$zipName" -Force

Write-Host "构建完成！ZIP 文件已保存到: $zipOutputDir\$zipName"

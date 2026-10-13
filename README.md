# LIHN WordPress 自动部署工具

一键安装命令：

apt-get update && apt-get install -y git && git clone https://github.com/libin8089/lihn-wordpress-deploy.git && cd lihn-wordpress-deploy && chmod 700 install.sh && bash install.sh

WordPress安装完成后进入管理后台地址：https://你的域名/wp-admin



用于在 Ubuntu 24.04 LTS 服务器上部署 WordPress 毛坯网站。

## 一、项目功能

- 自动检查操作系统、CPU、内存和磁盘空间
- 检查 HTTP 和 HTTPS 端口占用情况
- 支持交互式选择其他网站端口
- 检查域名 DNS 解析
- 自动安装 Nginx、PHP 8.3 和 MariaDB
- 自动下载并安装 WordPress
- 数据库用户名默认使用 adman_wp
- 数据库名称采用固定前缀和随机后缀
- 自动生成数据库密码和 WordPress 管理员密码
- 尝试自动申请 Let's Encrypt HTTPS 证书
- 输出网站、数据库和管理员安装信息
- 保护安装信息文件，避免普通用户读取

## 二、适用环境

- 操作系统：Ubuntu 24.04 LTS
- Web 服务：Nginx
- PHP：8.3
- 数据库：MariaDB
- 网站程序：WordPress

## 三、使用前的准备

1. 准备一台全新的 Ubuntu 24.04 服务器。
2. 确保服务器具有公网访问能力。
3. 将域名 A 记录解析到服务器公网 IPv4。
4. 检查云平台安全组的入站规则。
5. 确保 SSH 连接正常。
6. 建议至少预留 5GB 磁盘空间。

注意：如果服务器已经运行网站或 Web 服务，不要直接运行安装脚本。

## 四、获取部署脚本（脚本解释）

以 root 用户登录服务器。

安装 Git：

```bash
apt-get update
apt-get install -y git

克隆仓库：
git clone https://github.com/libin8089/lihn-wordpress-deploy.git

进入项目目录：
cd lihn-wordpress-deploy

检查脚本：
less install.sh

五、运行安装脚本
赋予脚本执行权限：
chmod 700 install.sh

运行：
bash install.sh

六、数据库信息
默认数据库用户名：
adman_wp
数据库名称采用固定前缀和随机后缀。
数据库密码由脚本随机生成。
安装完成后，请妥善保存数据库名称、用户名和密码。
注意：当前版本使用固定数据库用户名，不适合直接在同一服务器上重复部署多个网站。后续版本将完善多站点数据库隔离。

七、安装信息
安装信息文件：
/root/wordpress-install-info.txt
文件权限应限制为 root 用户读取。
查看安装信息：
cat /root/wordpress-install-info.txt
不要将该文件上传到 GitHub，也不要放到网站公开目录。

八、端口说明
默认 HTTP 端口：80  默认 HTTPS 端口：443
如果端口被占用，脚本会提示选择其他端口。
使用非标准端口时，需要在云平台安全组和本机防火墙中放行相应端口。
非标准 HTTP 端口不代表 HTTPS 可以自动配置成功。

九、HTTPS 说明

自动申请证书需要满足相应的域名验证条件。

如果使用 Let's Encrypt HTTP-01 验证，通常需要公网能够访问 80 端口。

如果无法使用标准端口，需要另行配置合适的证书验证方式。

安装完成后，请确认 HTTPS 实际可用，不要只根据脚本输出判断。

十、备份建议

建议定期备份：

WordPress 网站文件
WordPress 数据库
商品图片及上传文件
网站配置文件

可以通过 FinalShell 将备份下载到本地电脑。

GitHub 主要用于管理部署脚本和代码，不应作为唯一的完整网站备份位置。

十一、安全注意事项
不要将数据库密码提交到 GitHub。
不要公开分享安装信息文件。
不要为了安装网站而随意关闭防火墙。
不要在已有网站的服务器上直接运行安装脚本。
正式部署前，应先在测试服务器验证脚本。
定期更新 WordPress、PHP 和系统安全补丁。

十二、项目地址

GitHub：
https://github.com/libin8089/lihn-wordpress-deploy

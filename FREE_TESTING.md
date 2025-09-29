# 📱 免费iOS测试指南

本项目支持多种免费测试方式，无需付费Apple Developer账号。

## 🆓 方案1: 免费Apple ID真机测试 (推荐)

### 前提条件
- 需要Mac电脑
- 免费Apple ID账号
- iOS设备

### 操作步骤

1. **克隆项目到Mac**
   ```bash
   git clone https://github.com/tuyanshuai/scanner.git
   cd scanner
   ```

2. **打开Xcode项目**
   ```bash
   open PhoneScanner.xcodeproj
   ```

3. **配置签名**
   - 选择项目 → PhoneScanner target
   - Signing & Capabilities 标签页
   - 取消勾选 "Automatically manage signing"
   - 重新勾选 "Automatically manage signing"
   - Team: 选择你的Apple ID
   - Bundle ID已配置为: `com.tuyanshuai.phonescanner`

4. **连接设备并运行**
   - 连接iPhone/iPad到Mac
   - 在设备上信任此电脑
   - Xcode中选择你的设备
   - 点击运行 ▶️

5. **设备信任开发者**
   - 设置 → 通用 → VPN与设备管理
   - 信任开发者证书

### ⚠️ 注意事项
- **7天有效期**: 应用7天后需要重新安装
- **最多3台设备**: 免费账号最多支持3台设备
- **网络要求**: 需要连接到互联网进行签名验证

## 🖥️ 方案2: iOS模拟器测试 (当前可用)

GitHub Actions已自动配置模拟器编译：

1. **查看编译结果**
   - 访问: https://github.com/tuyanshuai/scanner/actions
   - 选择最新的 "iOS Build" 工作流
   - 查看编译日志

2. **在Mac上运行模拟器**
   ```bash
   # 模拟器编译 (无需签名)
   xcodebuild \
     -project PhoneScanner.xcodeproj \
     -scheme PhoneScanner \
     -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
     build
   ```

## 🌐 方案3: Web预览 (计划中)

考虑使用WebRTC技术创建Web版本的预览功能，完全在浏览器中测试核心功能。

## ❓ 常见问题

**Q: 为什么7天后应用消失？**
A: 免费Apple ID签名有时间限制，需要重新安装。

**Q: 能否延长使用时间？**
A: 免费账号无法延长，考虑升级到付费开发者账号($99/年)。

**Q: Windows用户如何测试？**
A: 使用GitHub Actions查看编译结果，或寻找有Mac的朋友协助。

## 📞 需要帮助？

如果遇到问题，可以：
1. 查看GitHub Issues
2. 检查Xcode控制台错误信息
3. 确保Apple ID账号状态正常
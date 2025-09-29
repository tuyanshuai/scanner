# PhoneScanner - iPhone 3D 扫描应用

这是一个利用iPhone前置TrueDepth摄像头进行3D数据采集和重建的iOS应用程序。

## 功能特性

- **前置3D摄像头支持**: 利用iPhone X及以上设备的TrueDepth摄像头
- **实时深度数据采集**: 获取高精度深度信息
- **3D点云处理**: 点云数据的滤波、配准和合并
- **图像拼接算法**: 多帧数据的自动拼接和融合
- **3D可视化**: 实时3D数据预览和交互
- **数据导出**: 支持PLY格式的点云数据导出

## 技术架构

### 核心组件

1. **DepthDataCapture.swift**
   - TrueDepth摄像头数据采集
   - AVFoundation框架集成
   - 深度数据和颜色数据同步

2. **PointCloudProcessor.swift**
   - 3D点云数据处理
   - ICP算法实现点云配准
   - 重复点去除和数据优化

3. **ImageStitcher.swift**
   - 特征点检测和匹配
   - RANSAC算法估计变换矩阵
   - 多帧数据的全局优化

4. **Renderer3D.swift**
   - Metal渲染引擎
   - 实时3D可视化
   - 交互式相机控制

### 使用的技术

- **ARKit**: 面部追踪和AR功能
- **AVFoundation**: 摄像头控制和数据采集
- **Metal**: 高性能GPU渲染
- **CoreImage**: 图像处理
- **simd**: 高性能数学运算

## 系统要求

- iOS 16.0+
- iPhone X或更新设备(支持TrueDepth摄像头)
- Xcode 15.0+
- Swift 5.0+

## 安装和运行

1. 克隆项目到本地
2. 用Xcode打开PhoneScanner.xcodeproj
3. 连接iPhone设备(必须支持TrueDepth摄像头)
4. 构建并运行应用

## 使用说明

1. **开始扫描**: 点击"开始扫描"按钮开始采集3D数据
2. **移动设备**: 缓慢移动iPhone以从不同角度采集数据
3. **停止扫描**: 再次点击按钮停止采集并开始处理
4. **查看结果**: 在下方的3D视图中查看重建结果
5. **交互控制**:
   - 拖拽旋转视角
   - 双指缩放调整距离
6. **保存数据**: 点击"保存"按钮保存点云数据
7. **导出数据**: 点击"导出"按钮以PLY格式分享数据

## 文件结构

```
PhoneScanner/
├── AppDelegate.swift          # 应用程序入口
├── SceneDelegate.swift        # 场景管理
├── ViewController.swift       # 主视图控制器
├── DepthDataCapture.swift     # 深度数据采集
├── PointCloudProcessor.swift  # 点云数据处理
├── ImageStitcher.swift        # 图像拼接算法
├── Renderer3D.swift          # 3D渲染引擎
├── Shaders.metal            # Metal着色器
├── Main.storyboard          # 界面布局
├── LaunchScreen.storyboard  # 启动界面
├── Info.plist              # 应用配置
└── Assets.xcassets/        # 资源文件
```

## 算法说明

### 深度数据采集
- 使用ARKit的面部追踪获取3D几何数据
- 结合AVFoundation获取TrueDepth摄像头的深度图
- 实时同步颜色和深度信息

### 点云配准
- 实现ICP(Iterative Closest Point)算法
- 使用RANSAC进行鲁棒估计
- 全局优化减少累积误差

### 图像拼接
- Harris角点检测
- 特征描述符计算和匹配
- PnP算法求解相机位姿
- Bundle Adjustment全局优化

## 性能优化

- 多线程处理避免界面阻塞
- Metal GPU加速渲染
- 内存管理和数据缓存优化
- 自适应算法参数调整

## 注意事项

- 需要良好的光照条件
- 保持设备稳定移动
- 避免快速移动造成模糊
- 确保扫描对象在合适距离内

## 扩展功能

未来可以添加的功能：
- 纹理映射
- 网格重建
- 多设备协同扫描
- 云端处理和存储
- AR预览和编辑

## 许可证

本项目仅供学习和研究使用。
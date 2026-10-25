# TAONIQ · 智道

黑白太极风格的原生 iOS 演示。输入生辰，以固定生辰核与随时间演化的流盘并排观察。

<img src="docs/screenshots/home.png" width="280" alt="智道首页：固定生辰核与连续流盘"> <img src="docs/screenshots/birth-input.png" width="280" alt="原生生辰输入页面">

## 在 Xcode 运行

1. 打开 `TAONIQ.xcodeproj`，选择 **TAONIQ** scheme。
2. 选择 iPhone 模拟器，按 **⌘R**。最低系统 iOS 18，无第三方 Swift 包、后端或账号要求。
3. 首次打开显示标记清楚的演示生辰。点右上角「生辰」，填写公历日期、时间与传统排运设定后生成。最近一次输入只保存在本机。
4. 单指拖动任一轨迹，两图同步改变视角；双指缩放，双击恢复视角。闲置时缓慢自动旋转。
5. 点「流盘演化」开始，点暂停停在当前时刻，再点继续沿同一条路径推进。默认每秒经过 7 个公历日，计算较慢时自动放缓。

真机运行需在 Xcode 的 Signing & Capabilities 中选择你自己的开发团队。本仓库不包含证书、账号或个人签名配置；模拟器可以关闭代码签名构建。

已在 Xcode 26.3 / iPhone 17 Pro（iOS 26.3 模拟器）构建并运行，10 项数值、几何与原生界面测试通过。尚未做真机续航或长期演化压力验证。

## 演化的含义

- 左图的出生参数、轨迹点固定，相机旋转只改变观看角度。
- 右图从出生时刻的冻结种子末点持续积分，新样点进入、旧样点退出。没有将两幅静态图片做形状插值。
- 大运、年、月、日、时保持既有默认输入预算，随真实干支边界更新目标参数；内部参数平滑响应。每公历日固定对应 `8/7` 模型单位。
- 暂停不会丢失状态；晚到结果先缓冲，继续时才显示。更换生辰建立新会话。进入后台暂停演化；系统「减少动态效果」设置下不自动旋转，仍可手动查看。
- 这是一套传统符号到人工动力系统的工程映射，不是命运预测。未知生辰沿用既有未校准预览；本演示不增加校准、命理解读或运势评分功能。

## 项目结构

| 路径 | 内容 |
| --- | --- |
| `TAONIQ/Views/` | SwiftUI 首页、生辰输入与黑白主题 |
| `TAONIQ/FlowStore.swift` | 输入、播放、暂停、后台与过时结果隔离 |
| `TAONIQ/Rendering/OrbitStage.swift` | SceneKit 三维轨迹、共同相机与拖拽 |
| `TAONIQ/Engine/` | JavaScriptCore 后台计算与原生数据桥 |
| `TAONIQ/Resources/` | 离线算法、历法依赖、哈希清单与许可 |
| `TAONIQTests/` / `TAONIQUITests/` | 数值与模拟器交互检查 |

算法来自 [TAONIQ v0.11](https://github.com/doyoulikelin-wq/TAONIQ/tree/80dc82ebb5503845fd3f0bd7fda8fb3351c6ac20)，公式、映射数据及连续积分源文件保持原样。详细口径见 [实现说明](docs/实现说明.md)，实际验收见 [验收记录](docs/验收记录.md)。

更新算法资源：`node scripts/sync-engine.cjs ../TAONIQ`。生成清单记录上游提交和源文件 SHA256；不要手改合并后的 `taoniq-engine.js`。

历法库 lunar-javascript 1.7.7 的 MIT 许可保存在 `TAONIQ/Resources/lunar-MIT-LICENSE.txt`。界面与太极图标由项目代码生成，不捆绑第三方字体或宗教画作。

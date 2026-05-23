# 美术资源说明

这个文件夹集中放置喵记账用到的美术资源，替换时尽量保持文件名、格式和大致比例不变。

## App 内图片

这些图片由 Flutter 页面直接通过 `assets/images/` 引用，已在 `pubspec.yaml` 中声明。

| 文件 | 用途 |
| --- | --- |
| `images/page_bg.png` | 所有页面最底层猫元素背景 |
| `images/login_bg.png` | 启动/登录页背景插画 |
| `images/home_page.png` | 首页顶部猫咪主视觉背景 |
| `images/cover_bg.png` | 首页顶部完整封面底图 |
| `images/app_icon.png` | App 内头像、关于我们、提醒页图标 |
| `images/app_name.png` | “喵记账”艺术字 Logo |
| `images/button_trimmed.png` | 猫爪主按钮底图 |
| `images/button.png` | 原始按钮图，当前保留备用 |
| `images/category_budget_empty_cat.png` | 分类预算空状态猫咪插画 |
| `images/guzi_avatar.png` | “谷子”等自定义分类头像 |
| `images/cat_paw.png` | 猫爪素材，当前保留备用 |
| `images/profile_picture.png` | 个人头像素材，当前保留备用 |

## 成就徽章

| 文件 | 对应成就 |
| --- | --- |
| `images/achievement_1.png` | 初次见面 |
| `images/achievement_2.png` | 三笔小账 |
| `images/achievement_3.png` | 十全十美 |
| `images/achievement_4.png` | 收入到账 |
| `images/achievement_5.png` | 预算守护 |
| `images/achievement_6.png` | 分类规划师 |
| `images/achievement_7.png` | 坚持记录 |
| `images/achievement_8.png` | 一周习惯 |
| `images/achievement_9.png` | 月度坚持 |
| `images/achievement_10.png` | 双月坚持 |
| `images/achievement_11.png` | 收支平衡 |
| `images/achievement_12.png` | 生活观察家 |

`achievement_12.png` 原本缺失，已先补为占位图。后续可以直接替换成正式的“生活观察家”徽章。

## 平台图标备份

`platform_icons/` 里是 Android、iOS、Web、Windows、macOS 启动图标和站点图标的集中备份，方便查找。

注意：这些备份文件不会自动影响构建。如果要修改真正的桌面/手机启动图标，需要同步替换对应平台目录里的文件，例如：

| 平台 | 真正生效目录 |
| --- | --- |
| Android | `android/app/src/main/res/mipmap-*` |
| iOS | `ios/Runner/Assets.xcassets/AppIcon.appiconset` |
| Web | `web/favicon.png`、`web/icons/` |
| Windows | `windows/runner/resources/app_icon.ico` |
| macOS | `macos/Runner/Assets.xcassets/AppIcon.appiconset` |

## 替换建议

- 普通页面图片：直接替换 `assets/images/` 下同名文件。
- App 内 Logo：替换 `images/app_name.png`。
- App 内头像图标：替换 `images/app_icon.png`。
- 启动图标：先替换平台目录，再按目标平台重新构建。
- 替换后建议运行 `flutter analyze`，再重新启动本地预览。

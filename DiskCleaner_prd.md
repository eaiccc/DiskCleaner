# DiskCleaner for macOS

## Product Requirements Document (PRD)

---

# 1. 產品概述

## 產品名稱

DiskCleaner for macOS

## 產品願景

協助使用者快速找出硬碟空間被誰佔用、哪些檔案可安全清理，並透過一鍵操作回收大量儲存空間。

## 目標使用者

### 一般使用者

- MacBook Air / Pro 使用者
- 容量不足使用者
- 不熟悉系統維護的使用者

### 專業使用者

- iOS 開發者
- Mac 開發者
- 影音工作者
- 設計師

---

# 2. 產品目標

### Goal 1

快速了解硬碟空間使用情況

### Goal 2

自動找出可安全刪除的內容

### Goal 3

一鍵清理釋放空間

### Goal 4

降低誤刪風險

---

# 3. 核心功能

## F001 硬碟空間分析

### 功能描述

掃描所有磁碟並分析容量使用情況。

### 支援磁碟

- Macintosh HD
- 外接硬碟
- USB 儲存裝置
- NAS 掛載磁碟

### 顯示內容

#### 容量資訊

| 項目 | 說明 |
|--------|--------|
| 總容量 | Disk Size |
| 已使用 | Used Space |
| 可用容量 | Free Space |
| 使用率 | Usage Percentage |

#### 視覺化圖表

以圓餅圖呈現：

- Applications
- Documents
- Photos
- Videos
- Developer
- System
- Others

### 驗收條件

- 掃描完成時間 < 30 秒
- 支援 1TB 以上磁碟

---

## F002 大型資料夾排行

### 功能描述

列出佔用空間最大的資料夾。

### 顯示內容

| 排名 | 路徑 | 容量 |
|--------|--------|--------|
| 1 | ~/Library/Developer | 95GB |
| 2 | ~/Downloads | 45GB |
| 3 | ~/Movies | 30GB |

### 功能需求

- 支援排序
- 支援搜尋
- 支援展開子資料夾
- 支援快速定位 Finder

### 驗收條件

- 可列出 Top 100 資料夾
- 支援即時搜尋

---

## F003 智慧整理建議

### 功能描述

根據掃描結果自動產生整理建議。

### 類型一：Cache

掃描位置：

```text
~/Library/Caches
```

建議內容：

- Chrome Cache
- Safari Cache
- Slack Cache
- Discord Cache

顯示：

```text
可安全清理
預估釋放 8.5GB
```

---

### 類型二：Downloads

規則：

- 超過 30 天未存取
- 檔案大於 1GB

建議內容：

- ISO
- ZIP
- DMG
- MP4
- MOV

---

### 類型三：大型檔案

規則：

```text
檔案大小 > 1GB
```

顯示：

- 路徑
- 容量
- 最後開啟時間

---

### 類型四：未使用 App

規則：

```text
180 天未開啟
```

顯示：

- App 名稱
- 容量
- 最後使用日期

---

### 驗收條件

- 至少提供三種清理建議
- 顯示預估可回收空間

---

## F004 Xcode 開發者模式

### 功能描述

專門針對 Apple 開發者進行空間分析。

### 掃描目錄

#### DerivedData

```text
~/Library/Developer/Xcode/DerivedData
```

#### Archives

```text
~/Library/Developer/Xcode/Archives
```

#### Simulators

```text
~/Library/Developer/CoreSimulator
```

#### Device Support

```text
~/Library/Developer/Xcode/iOS DeviceSupport
```

### 顯示內容

| 類型 | 容量 |
|--------|--------|
| DerivedData | 35GB |
| Archives | 12GB |
| Simulators | 8GB |
| Device Support | 3GB |

### 驗收條件

- 正確辨識 Xcode 資料夾
- 可獨立勾選清理

---

## F005 重複檔案分析

### 功能描述

透過 Hash 比對尋找重複檔案。

### 技術方式

```text
SHA256
```

### 顯示內容

| 檔案 | 數量 | 可回收 |
|--------|--------|--------|
| Vacation.mov | 3 | 8GB |

### 驗收條件

- 不誤判不同檔案
- 保留至少一份原始檔

---

## F006 一鍵清理

### 功能描述

勾選項目後執行批次清理。

### UI

```text
☑ Cache
☑ DerivedData
☑ Simulators
☐ Downloads
☐ Duplicate Files
```

### 顯示內容

```text
預計釋放：
63.4 GB
```

### 清理流程

1. 勾選項目
2. 顯示預估容量
3. 確認執行
4. 顯示進度
5. 顯示結果

### 驗收條件

- 可顯示即時進度
- 支援取消

---

# 4. 安全機制

## S001 系統目錄保護

禁止清理：

```text
/System
/usr
/bin
/sbin
/private
```

---

## S002 二次確認

顯示：

```text
即將刪除：
12.3GB

是否繼續？
```

---

## S003 垃圾桶模式

預設：

```text
Move to Trash
```

避免直接永久刪除。

---

## S004 復原機制

保留：

```text
最近 7 天清理紀錄
```

支援還原。

---

# 5. 空間健康分數

## 功能描述

以 100 分評估磁碟健康程度。

### 評分項目

| 指標 | 權重 |
|--------|--------|
| 剩餘空間比例 | 40% |
| Cache 佔用 | 20% |
| 重複檔案 | 15% |
| Downloads 堆積 | 15% |
| 未使用 App | 10% |

### 顯示

```text
Storage Health Score

92 / 100
```

---

# 6. 非功能需求

## 效能

- 掃描速度 < 30 秒
- UI 不可卡頓
- 背景執行

## 穩定性

- 不可造成 Finder Crash
- 不可誤刪系統檔案

## 隱私

- 不上傳檔案
- 所有分析於本機完成

---

# 7. MVP 範圍

## Included

- 磁碟掃描
- 圓餅圖
- 大型資料夾排行
- Cache 清理
- Downloads 建議
- Xcode 清理
- 一鍵清理

## Excluded

- AI Agent
- NAS 管理
- 雲端同步
- 排程清理

---

# 8. V2 規劃

## AI 智慧建議

分析使用習慣：

```text
最近 90 天未開啟檔案
```

推薦搬移或刪除。

## 自動清理

排程：

- 每週
- 每月

自動執行。

## Menu Bar Mode

常駐 Menu Bar：

```text
Storage:
85% Used
```

即時提醒。

---

# 9. 技術架構

## Frontend

- SwiftUI

## Storage

- SwiftData

## Scan Engine

- FileManager
- URLResourceValues

## Charts

- Swift Charts

## Permission

- App Sandbox
- Security Scoped Bookmark

## Supported OS

- macOS 14 Sonoma+
- macOS 15 Sequoia+

---

# 10. 市場定位

## 競品

- DaisyDisk
- CleanMyMac
- GrandPerspective

## 差異化

### 開發者優先

提供：

- DerivedData 清理
- Simulator 清理
- Archive 清理

### AI 整理建議

依據使用行為推薦清理項目。

### 本機運算

不上傳任何個人檔案。


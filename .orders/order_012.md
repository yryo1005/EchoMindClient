# order_012

## ユーザーの指示

> 実機で動かすために必要なこと
> 1,2まではできたけど3のBundle Identifierは何？Xcodeにある？

## 指示の解釈

- order_011で案内した実機の準備のうち，iPhoneのデベロッパモードの有効化とXcodeのアカウントへのサインインは完了したという報告である．
- Bundle Identifierの意味とXcode上の場所を説明する．あわせて，プロジェクトファイルの`PRODUCT_BUNDLE_IDENTIFIER`を仮の値から`com.yryo1005.EchoMindClient`に変更し，実機向けのビルドとインストールを行う．

## 対応結果

- Bundle Identifierを`com.yryo1005.EchoMindClient`に変更し，`xcodebuild -allowProvisioningUpdates`で実機向けにビルドした．プロビジョニングプロファイル「iOS Team Provisioning Profile: com.yryo1005.EchoMindClient」が自動で作成された．
- `devicectl`でiPhone 16 Pro Maxにインストールできたが，起動は「開発元が信頼されていない」ため拒否された(FBSOpenApplicationErrorDomain error 3)．iPhoneの「設定」→「一般」→「VPNとデバイス管理」で開発元を信頼する必要がある．

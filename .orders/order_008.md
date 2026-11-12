# order_008

## ユーザーの指示

> 新規登録しようとした際に
> KeyChainへの保存に失敗しました OSStatus: -34018，とでます

## 指示の解釈

- Step 1(order_007)の確認中に，シミュレーターでの新規登録時にKeychainへの保存がエラー(-34018，errSecMissingEntitlement)になったという報告である．原因を調べて解消する．

## 調査結果と対応

- シミュレーターに入っていたアプリは，AIエディタが動作確認のために`CODE_SIGNING_ALLOWED=NO`(署名なし)でビルドしてインストールしたものであった．署名なしのビルドには`application-identifier`のエンタイトルメントが含まれず，シミュレーターのKeychainが使えない．
- アプリのコードの問題ではない．Xcodeから実行(⌘R)した場合や，署名を有効にしてビルドした場合は`application-identifier`が付与される．
- 署名を有効にしてビルドし直し，iPhone 17のシミュレーターのアプリを入れ替えた．

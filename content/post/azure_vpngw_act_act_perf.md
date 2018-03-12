+++
Categories = ["Azure"]
Tags = ["Azure", "VPN Gateway", "Network"]
date = "2017-10-08T10:30:00+09:00"
title = "Azure VPN Gateway Active/Active構成のスループット検証(リージョン内)"

+++

## 動機
[焦げlogさん](https://kogelog.com/)で、とても興味深いエントリを拝見しました。

* [Azure VPN ゲートウェイをアクティブ/アクティブ構成した場合にスループットが向上するのか検証してみました](https://kogelog.com/2017/10/06/20171006-01/)

確かにActive/Active構成にはスループット向上を期待したくなります。その伸びが測定されており、胸が熱くなりました。ですが、ちょっと気になったのは

> ※それと、VpnGw3 よりも VpnGw2 のほうがスループットがよかったのが一番の謎ですが…

ここです。VPN GatewayのSKU、VpnGw3とVpnGw2には小さくない価格差があり、その基準はスループットです。ここは現状を把握しておきたいところ。すごく。

そこで、焦げlogさんの検証パターンの他に、追加で検証しました。それは同一リージョン内での測定です。リージョン内でVPNを張るケースはまれだと思いますが、リージョンが分かれることによる

* 遅延
* リージョン間通信に関するサムシング

を除き、VPN Gateway自身のスループットを測定したいからです。焦げlogさんの測定は東日本/西日本リージョン間で行われたので、その影響を確認する価値はあるかと考えました。

## 検証方針
* 同一リージョン(東日本)に、2つのVNETを作る
* それぞれのVNETにVPN Gatewayを配置し、接続する
* 比較しやすいよう、焦げlogさんの検証と条件を合わせる
  * 同じ仮想マシンサイズ: DS3_V2
  * 同じストレージ: Premium Storage Managed Disk
  * 同じOS: Ubuntu 16.04
  * 同じツール: ntttcp
  * 同じパラメータ: ntttcp -r -m 16,*,<IP> -t 300
* 送信側 VNET1 -> 受信側 VNET2 のパターンに絞る
* スループットのポテンシャルを引き出す検証はしない

## 結果

### VpnGW1(650Mbps)

|パターン　|送信側GW構成　　　　　|受信側GW構成　　　　　　　　|送信側スループット　|　受信側スループット|　スループット平均|　パターン1との比較|
|  :-----------  |  :-----------  |  :------------  |  ------------:  |  ------------:  |  ------------:  |  ------------:  |
|パターン1　|  Act/Stb  |  Act/Stb  |677.48Mbps|676.38Mbps|676.93Mbps|-|
|パターン2　|  Act/Stb  |  Act/Act  |674.34Mbps|673.85Mbps|674.10Mbps|99%|
|パターン3　|  Act/Act  |  Act/Act  |701.19Mbps|699.91Mbps|700.55Mbps|103%|


### VpnGW2(1Gbps)

|パターン　|送信側GW構成　　　　　|受信側GW構成　　　　　　　　|送信側スループット　|　受信側スループット|　スループット平均|　パターン1との比較|
|  :-----------  |  :-----------  |  :------------  |  ------------:  |  ------------:  |  ------------:  |  ------------:  |
|パターン1　|  Act/Stb  |  Act/Stb  |813.09Mbps|805.60Mbps|809.35Mbps|-|
|パターン2　|  Act/Stb  |  Act/Act  |1.18Gbps|1.18Gbps|1.18Gbps|149%|
|パターン3　|  Act/Act  |  Act/Act  |2.03Gbps|2.02Gbps|2.03Gbps|256%|


### VpnGW3(1.25Gbps)

|パターン　|送信側GW構成　　　　　|受信側GW構成　　　　　　　　|送信側スループット　|　受信側スループット|　スループット平均|　パターン1との比較|
|  :-----------  |  :-----------  |  :------------  |  ------------:  |  ------------:  |  ------------:  |  ------------:  |
|パターン1　|  Act/Stb  |  Act/Stb  |958.56Mbps|953.72Mbps|956.14Mbps|-|
|パターン2　|  Act/Stb  |  Act/Act  |1.39Gbps|1.39Gbps|1.39Gbps|149%|
|パターン3　|  Act/Act  |  Act/Act  |2.19Gbps|2.19Gbps|2.19Gbps|234%|


### SKU視点 パターン1(Act/Stb to Act/Stb)
|SKU　|　スループット平均|　VpnGw1との比較|
|  :-----------  |  ------------:  |  ------------:  |
|VpnGw1　|676.93Mbps|-|
|VpnGw2　|809.35Mbps|119%|
|VpnGw3　|956.14Mbps|141%|

### SKU視点 パターン2(Act/Stb to Act/Act)
|SKU　|　スループット平均|　VpnGw1との比較|
|  :-----------  |  ------------:  |  ------------:  |
|VpnGw1　|674.10Mbps|-|
|VpnGw2　|1.18Gbps|179%|
|VpnGw3　|1.39Gbps|211%|

### SKU視点 パターン3(Act/Act to Act/Act)
|SKU　|　スループット平均|　VpnGw1との比較|
|  :-----------  |  ------------:  |  ------------:  |
|VpnGw1　|700.55Mbps|-|
|VpnGw2　|2.03Gbps|297%|
|VpnGw3　|2.19Gbps|320%|


## 考察と推奨
* リージョン間の遅延やサムシングを除くと、SKUによるGatewayのスループット差は測定できる
  * Act/Actでないパターン1(Act/Stb to Act/Stb)で、その差がわかる
* 公式ドキュメントの通り、GatewayのAct/Act構成は可用性向上が目的であるため、スループットの向上はボーナスポイントと心得る
  * 期待しちゃうのが人情ではありますが
  * VpnGw2がコストパフォーマンス的に最適という人が多いかもしれませんね 知らんけど
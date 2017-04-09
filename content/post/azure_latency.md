+++
Categories = ["Azure"]
Tags = ["Azure", "Network", "Latency"]
date = "2017-04-09T15:15:00+09:00"
title = "AzureのLatency測定 2017/4版"

+++

## 関東の片隅で遅延を測る
Twitterで「東阪の遅延って最近どのくらい？」と話題になっていたので。首都圏のAzureユーザー視線で測定しようと思います。

せっかくなので、

* 太平洋のそれも測定しましょう
* [Azureバックボーンを通るリージョン間通信](https://azure.microsoft.com/en-us/blog/how-microsoft-builds-its-fast-and-reliable-global-network/)も測りましょう

## 計測パターン

1. 自宅(神奈川) -> OCN光 -> インターネット -> Azure東日本リージョン
2. 自宅(神奈川) -> OCN光 -> インターネット -> Azure西日本リージョン
3. 自宅(神奈川) -> OCN光 -> インターネット -> Azure米国西海岸リージョン
4. Azure東日本リージョン -> Azureバックボーン -> Azure西日本リージョン
5. Azure東日本リージョン -> Azureバックボーン -> Azure米国西海岸リージョン

## もろもろの条件

* 遅延測定ツール
  * [PsPing](https://technet.microsoft.com/en-us/sysinternals/psping.aspx)
  * Azure各リージョンにD1_v2/Windows Server 2016仮想マシンを作成しPsPing
  * NSGでデフォルト許可されているRDPポートへのPsPing
  * VPN接続せず、パブリックIPへPsPing
  * リージョン間PsPingは仮想マシンから仮想マシンへ
* 自宅Wi-Fi環境
  * 802.11ac(5GHz)
* 自宅加入インターネット接続サービス
  * OCN 光 マンション 100M
* OCNゲートウェイ
  * (ほげほげ)hodogaya.kanagawa.ocn.ne.jp
  * 神奈川県横浜市保土ケ谷区の局舎からインターネットに出ているようです
* 米国リージョン
  * US WEST (カリフォルニア)

## 測定結果

### 1. 自宅(神奈川) -> OCN光 -> インターネット -> Azure東日本リージョン

```
TCP connect statistics for 104.41.187.55:3389:
  Sent = 4, Received = 4, Lost = 0 (0% loss),
  Minimum = 11.43ms, Maximum = 15.66ms, Average = 12.88ms
```

### 2. 自宅(神奈川) -> OCN光 -> インターネット -> Azure西日本リージョン

```
TCP connect statistics for 52.175.148.28:3389:
  Sent = 4, Received = 4, Lost = 0 (0% loss),
  Minimum = 17.96ms, Maximum = 19.64ms, Average = 18.92ms
```

### 3. 自宅(神奈川) -> OCN光 -> インターネット -> Azure米国西海岸リージョン

```
TCP connect statistics for 40.83.220.19:3389:
  Sent = 4, Received = 4, Lost = 0 (0% loss),
  Minimum = 137.73ms, Maximum = 422.56ms, Average = 218.85ms
```

### 4. Azure東日本リージョン -> Azureバックボーン -> Azure西日本リージョン

```
TCP connect statistics for 52.175.148.28:3389:
  Sent = 4, Received = 4, Lost = 0 (0% loss),
  Minimum = 8.61ms, Maximum = 9.38ms, Average = 9.00ms
```

### Azure東日本リージョン -> Azureバックボーン -> Azure米国西海岸リージョン

```
TCP connect statistics for 40.83.220.19:3389:
  Sent = 4, Received = 4, Lost = 0 (0% loss),
  Minimum = 106.38ms, Maximum = 107.38ms, Average = 106.65ms
```

Azureバックボーンを通すと首都圏からの遅延が半分になりました。Wi-Fiの有無など、ちょっと条件は違いますが。

## ひとこと

インターネット、および接続サービスの遅延が性能の上がらない原因になっている場合は、Azureで完結させてみるのも手です。

たとえば、

* 会社で契約しているインターネット接続サービスが、貧弱
* シリコンバレーの研究所からインターネット経由でデータを取得しているが、遅い

こんなケースではAzureを間に入れると、幸せになれるかもしれません。なったユーザーもいらっしゃいます。
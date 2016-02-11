+++
Categories = ["Azure"]
Tags = ["Azure", "Blob", "Upload"]
date = "2016-02-11T12:00:00+09:00"
title = "Azure Blob Upload ツール別ベンチマーク"

+++

## 同じ目的を達成できるツールがたくさん
やりたいことがあり、それを達成する手段がたくさん。どう選ぼう。じゃあ特徴を知りましょう。という話です。

端末からAzureへファイルをアップロードする手段は多くあります。CLIツール、GUIツール、SDKで自作する、etc。

そして、端末と、そのおかれている環境も多様です。Windows、Mac。有線、無線。

で、大事なのは並列度。ブロックBlobはブロックを並列に転送する方式がとれるため、ツールが並列転送をサポートしているか? どのくらい効くのか? は重要な評価ポイントです。

なので、どのツールがおすすめ?と聞かれても、条件抜きでズバっとは答えにくい。そしてこの質問は頻出。なのでこんな記事を書いています。

## 環境と測定方式
おそらくファイルを送る、という用途でもっとも重視すべき特徴は転送時間でしょう。ではツール、環境別に転送時間を測定してみます。

環境は以下の通り。

* Windows端末
    * Surface Pro 4 Core i7/16GB Memory/802.11ac
    * 1Gbps Ethernet (USB経由)
    * Windows 10 (1511)
* Mac端末
    * Macbook 12inch Core M/8GB Memory/802.11ac
    * USB-C... 有線テストは省きます
    * El Capitan
*  Wi-Fiアクセスポイント/端末間帯域
    * 100~200Mbpsでつながっています
* Azureデータセンタまでの接続
    * 日本マイクロソフトの品川オフィスから、首都圏にあるAzure Japan Eastリージョンに接続
    * よってWAN側の遅延、帯域ともに条件がいい
* 対象ツール
    * [AzCopy v5.0.0.27](https://azure.microsoft.com/ja-jp/documentation/articles/storage-use-azcopy/) (Windowsのみ)
    * [Azure CLI v0.9.15](https://azure.microsoft.com/ja-jp/documentation/articles/xplat-cli-install/)
    * [Azure Storage Explorer - Cross Platform GUI v0.7](http://storageexplorer.com/)
* 転送ファイル
    * Ubuntu 15.10 ISOイメージ (647MBytes)

そして測定方式。

AzCopyはPowerShellのMeasure-Commandにて実行時間をとります。NCが並列度指定です。デフォルトの並列度はCPUコア数の8倍です。わしのSurface、OSから4コア見えていますので、32。

    Measure-Command {AzCopy /Source:C:\Users\myaccount\work /Dest:https://myaccount.blob.core.windows.net/mycontainer /DestKey:mykey /Pattern:ubuntu-15.10-server-amd64.iso /Y /NC:count}

Azure CLIも同様にMeasure-Commandで。--concurrenttaskcountで並列度を指定できますが、[ソース](https://github.com/Azure/azure-xplat-cli/blob/dev/lib/util/storage.util._js)を確認したところ、並列度のデフォルトは5です。"StorageUtil.threadsInOperation = 5;"ですね。

    Measure-Command {azure storage blob upload ./ubuntu-15.10-server-amd64.iso -a myaccount -k mykey mycontainer ubuntu1510 --concurrenttaskcount count}

残念ながらMacむけAzCopyはありませんので、Azure CLIのみ実行します。timeコマンドで時間をとります。

    time azure storage blob upload ./ubuntu-15.10-server-amd64.iso -a myaccount -k mykey mycontainer ubuntu1510 --concurrenttaskcount count
    
Azure Storage Explorer Cross Platform GUIは、目視+iPhoneのストップウォッチで。 

## 結果
並列度上げても伸びないな、というタイミングまで上げます。

|  No  |  OS  |  接続  |  クライアント  |  並行数  |  転送時間(秒)  |
|-----------:|:-----------|:------------|:------------|------------:|------------:|
|1|Windows 10|1Gbps Ethernet|AzCopy|(default:32)|9.62|
|2|Windows 10|1Gbps Ethernet|AzCopy|5|12.28|
|3|Windows 10|1Gbps Ethernet|AzCopy|10|10.83|
|4|Windows 10|1Gbps Ethernet|AzCopy|20|10.43|
|5|Windows 10|1Gbps Ethernet|Azure CLI|(default:5)|49.92|
|6|Windows 10|1Gbps Ethernet|Azure CLI|10|29.47|
|7|Windows 10|1Gbps Ethernet|Azure CLI|20|21.05|
|8|Windows 10|1Gbps Ethernet|Azure CLI|40|20.12|
|9|Windows 10|1Gbps Ethernet|Azure Storage Explorer|N/A|50.10|
|10|Windows 10|802.11ac|AzCopy|(default:32)|74.87|
|11|Windows 10|802.11ac|AzCopy|5|53.32|
|12|Windows 10|802.11ac|AzCopy|10|58.85|
|13|Windows 10|802.11ac|Azure CLI|(default:5)|57.23|
|14|Windows 10|802.11ac|Azure CLI|10|50.71|
|15|Windows 10|802.11ac|Azure CLI|20|54.37|
|16|Windows 10|802.11ac|Azure Storage Explorer|N/A|54.63|
|17|Mac OS X|802.11ac|Azure CLI|(default:5)|40.86|
|18|Mac OS X|802.11ac|Azure CLI|10|33.97|
|19|Mac OS X|802.11ac|Azure CLI|20|58.57|
|20|Mac OS X|802.11ac|Azure Storage Explorer|N/A|58.20|

## 考察
* 有線AzCopy早い。単純計算で67MByte/s(480Mbps)出ています。それぞれの計測点の解釈の違いでBlobサービス制限の60MBytes/sを超えてしまっていますがw。データセンタまでのボトルネックがなければ、ポテンシャルを引き出せることがわかります。
* 並列度は大きく性能に影響します。
    * 並列度が高すぎてもだめ
        * 無線AzCopyのデフォルト(並列度32)が並列度10、20より時間がかかっていることからわかる
    * デフォルトで遅いからといってあきらめず、並列度変えて試してみましょう
    * SDK使って自分で作る時も同じ。並列度パラメータを意識してください
        * .NET: BlobRequestOptions
        * Java/Android: BlobRequestOptions.setConcurrentRequestCount()
        * Node.js: parallelOperationThreadCount
        * C++: blob_request_options::set_parallelism_factor
* Azure CLIよりAzCopyが早い。
    * .NETで最適化できているから合点
    * Node.jsベースでマルチOS対応のAzure CLIは比べられると分が悪い
    * でも、802.11acでも無線がボトルネックになっているので、いまどきのWi-Fi環境では似たような性能になる
    * No.18の結果は無線状態がよかったと想定
* Azure Storage Explorer Cross Platform GUIは、現時点で並列度変えられないので性能面では不利。でも直観的なので、使い分け。

WAN条件がいいベンチマークでなので、ぜひみなさんの条件でも試してみてください。遅延の大きなリージョンや途中に帯域ボトルネックがある条件でやると、最適な並列度が変わってくるはずです。


でも一番言いたかったのは、Macbookの有線アダプタ欲しいということです。
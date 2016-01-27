+++
Categories = ["Azure"]
Tags = ["Azure", "Cloud", "Performance"]
date = "2016-01-24T00:19:00+09:00"
title = "クラウドは本当に性能不足なのか"

+++

**このエントリは2016/1/24に書きました。使えるリソースはどんどん増えていくので、適宜その時点で情報をとってください。**

## 具体的な数値で、正しい理解を
["クラウドは性能不足、企業システムが重すぎる"](http://itpro.nikkeibp.co.jp/atcl/watcher/14/334361/011800463/)という記事が身の回りで話題になりました。公開から4日たっても「いま読まれている記事」の上位にあり、注目されているようです。

記事で訴えたかったことは、クラウドを過信しないように、そして、クラウドはクラウドらしい使い方をしよう、ということでしょう。ユーザの声は貴重ですし、同意できるところも多い。でも、「企業システム」とひとくくりにしてしまったこと。タイトルのバイアスが強いこと。そして、具体的な根拠に欠けることから、誤解を招いている印象です。

どんな技術、製品、サービスにも限界や制約はあります。具体的な数値や仕様で語らないと、そこから都市伝説が生まれます。

いい機会なので、わたしの主戦場であるAzureを例に、クラウドでどのくらいの性能を期待できるか、まとめてみようと思います。

## シングルVMでどれだけ
話題となった記事でも触れられているように、クラウドはその生まれから、分散、スケールアウトな作りのアプリに向いています。ですが世の中には「そうできない」「そうするのが妥当ではない」システムもあります。記事ではそれを「企業システム」とくくっているようです。

わたしは原理主義者ではないので「クラウドに載せたかったら、そのシステムを作り直せ」とは思いません。作りを大きく変えなくても載せられる、それでクラウドの特徴を活かして幸せになれるのであれば、それでいいです。もちろん最適化するにこしたことはありませんが。

となると、クラウド活用の検討を進めるか、あきらめるか、判断材料のひとつは「スケールアウトできなくても、性能足りるか?」です。

この場合、1サーバ、VMあたりの性能上限が制約です。なので、AzureのシングルVM性能が鍵になります。

では、Azureの仮想マシンの提供リソースを確認しましょう。

["仮想マシンのサイズ"](https://azure.microsoft.com/ja-jp/documentation/articles/virtual-machines-size-specs/)

ざっくりA、D、Gシリーズに分けられます。Aは初期からあるタイプ。ＤはSSDを採用した現行の主力。Gは昨年後半からUSリージョンで導入がはじまった、大物です。ガンダムだと後半、宇宙に出てから登場するモビルアーマー的な存在。現在、GシリーズがもっともVMあたり多くのリソースを提供できます。

企業システムではOLTPやIOバウンドなバッチ処理が多いと仮定します。では、Gシリーズ最大サイズ、Standard_GS5の主な仕様から、OLTPやバッチ処理性能の支配要素となるCPU、メモリ、IOPSを見てみましょう。

* Standard_GS5の主な仕様
    * 32仮想CPUコア
    * 448GBメモリ
    * 80,000IOPS

メモリはクラウドだからといって特記事項はありません。クラウドの特徴が出るCPUとIOPSについて深掘りしていきます。

なお、**現時点で**まだ日本リージョンにはGシリーズが投入されていません。必要に応じ、公開スペックと後述のACUなどを使ってA、Dシリーズと相対評価してください。

## 32仮想CPUコアの規模感
クラウドのCPU性能表記は、なかなか悩ましいです。仮想化していますし、CPUは世代交代していきます。ちなみにAzureでは、ACU(Azure Compute Unit)という単位を使っています。

["パフォーマンスに関する考慮事項"](https://azure.microsoft.com/ja-jp/documentation/articles/virtual-machines-size-specs/#-3)

ACUはAzure内で相対評価をする場合にはいいのですが、「じゃあAzureの外からシステムもってきたとき、実際どのくらいさばけるのよ。いま持ってる/買えるサーバ製品でいうと、どのくらいよ」という問いには向きません。

クラウドや仮想化に関わらず、アプリの作りと処理するデータ、ハードの組み合わせで性能は変わります。動かしてみるのが一番です。せっかくイニシャルコストのかからないクラウドです。試しましょう。でもその前に、試す価値があるか判断しなければいけない。なにかしらの参考値が欲しい。予算と組織で動いてますから。わかります。

では例をあげましょう。**俺のベンチマーク**を出したいところですが、「それじゃない」と突っ込まれそうです。ここはぐっと我慢して、企業でよく使われているERP、SAPのSAP SDベンチマークにしましょう。

["SAP Standard Application Benchmarks in Cloud Environments"](http://global.sap.com/campaigns/benchmark/appbm_cloud.epx)

["SAP Standard Application Benchmarks"](http://global.sap.com/campaigns/benchmark/index.epx)

SAPSという値が出てきます。販売管理アプリケーションがその基盤上でどれだけ仕事ができるかという指標です。

比較のため、3年ほど前の2ソケットマシン、現行2ソケットマシン、現行4ソケットマシンを選びました。単体サーバ性能をみるため、APとDBを1台のサーバにまとめた、2-Tierの値をとります。

|               |[DELL R720](http://download.sap.com/download.epd?context=40E2D9D5E00EEF7C91D3C5AFFF9A4689C82EA97027CDF4A42858AD1610A3F732) |[Azure VM GS5](http://global.sap.com/campaigns/benchmark/assets/Cert15038.pdf) | [NEC R120f-2M](http://download.sap.com/download.epd?context=40E2D9D5E00EEF7CFDB9CAEA540B6F601993E4359AB45BEF7ED0949D1BFF155D) | [FUJITSU RX4770 M2](http://download.sap.com/download.epd?context=40E2D9D5E00EEF7C14B03FD143D20C6C90E8F6DEAA4E15F8090BA77A6249E1D0)  |
|:-----------|:------------|:------------|:------------|:------------|
|Date|2012/4|2015/9|2015/7|2015/7|
| CPU Type |Intel Xeon Processor E5-2690| Intel Xeon Processor E5-2698B v3 | Intel Xeon Processor E5-2699 v3 | Intel Xeon Processor E7-8890 v3 |
| CPU Sockets |2 | 2 | 2 | 4 |
| CPU Cores|16 | 32 (Virtual) | 36 | 72 |
| SD Benchmark Users |6,500| 7,600 | 14,440 | 29,750 |
| SAPS |35,970| 41,670 | 79,880 | 162,500 |
 
 
 3年前の2ソケットマシンより性能はいい。現行2ソケットマシンの半分程度が期待値でしょうか。ざっくりE5-2699 v3の物理18コアくらい。4ソケットは無理め。
 
 なお補足ですが、もちろんSAPはAPサーバをスケールアウトする構成もとれます。その性能は[3-Tierベンチマーク](http://global.sap.com/campaigns/benchmark/appbm_cloud.epx)で確認できます。[Azure上で247,880SAPS](http://blogs.msdn.com/b/saponsqlserver/archive/2015/10/05/world-record-sap-sales-and-distribution-standard-application-benchmark-for-sap-cloud-deployments-released-using-azure-iaas-vms.aspx)出たそうです。

## 80,000IOPSの規模感
IOPS = IO Per Second、秒あたりどれだけIOできるかという指標です。Azure VM GS5では[Premium Storage](https://azure.microsoft.com/ja-jp/documentation/articles/storage-premium-storage-preview-portal/)を接続し、VMあたり最大80,000IOPSを提供します。

一般的に企業で使われているディスクアレイに載っているHDDのIOPSは、1本あたりおおよそ200です。IOPSに影響する要素は回転数で、よく回る15,000rpm FC/SAS HDDでだいたいこのくらい。

なので80,000 / 200 = 400。よって80,000IOPSを達成しようとすると、HDDを400本並べないといけません。小さくないです。

もちろんディスクアレイにはキャッシュがあるので、キャッシュヒット次第でIOPSは変わります。ベンダが胸を張って公開している値も、キャッシュに当てまくった数字であることが多いです。ですが誠実な技術者は「水物」なキャッシュヒットを前提にサイジングしません。アプリがアレイを占有できて、扱うデータの量や中身に変化がない場合は別ですが、それはまれでしょう。ヒットしない最悪の場合を考慮するはずです。

なお、数十万IOPSをこえるディスクアレイがあるのは事実です。でも「桁が違う。クラウドしょぼい」と思わないでください。ディスクアレイ全体の性能と、VMあたりどのくらい提供するかは、別の問題です。ひとつのVMがディスクアレイを占有するのでない限り、VMあたりのIOコントロールは必要です。そうでないと、暴れん坊VMの割を食うVMがでてきます。見えていないだけで、クラウドのバックエンドにはスケーラブルなストレージが鎮座しています。

## 結論

* Intel x86 2ソケットモデルサーバで動いているようなシステムの移行であれば検討価値あり
* メモリが448GB以上必要であれば難しい
* サーバあたり80,000IOPS以上必要であれば難しい、でも本当にサーバあたりそれだけ必要か精査すべき

ちょっと前までオンプレ案件も担当していましたが、ここ数年は2ソケットサーバ案件中心、ときどき、4ソケット以上で興奮。という感覚です。みなさんはいかがでしょう。データはないのでご参考まで。

なにはともあれ、プロのみなさんは噂に流されず、制約を数値で把握して判断、設計しましょう。Azureではそのほかの制約条件も公開されていますので、ぜひご一読を。上限を緩和できるパラメータも、あります。
 
 ["Azure サブスクリプションとサービスの制限、クォータ、制約"](https://azure.microsoft.com/ja-jp/documentation/articles/azure-subscription-service-limits/)
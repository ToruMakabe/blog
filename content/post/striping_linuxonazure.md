+++
Categories = ["Azure"]
Tags = ["Azure", "Linux", "Disk", "Performance"]
date = "2016-01-27T00:19:30+09:00"
title = "Linux on AzureでDisk IO性能を確保する方法"

+++

## "俺の鉄板"ができるまで
前半はポエムです。おそらくこのエントリたどり着く人の期待はLinux on AzureのDisk IO性能についてと思いますが、それは後半に書きます。

クラウド、Azureに関わらず、技術や製品の組み合わせは頭の痛い問題です。「これとこれ、組み合わせて動くの？サポートされるの？性能出るの？」という、あれです。技術や製品はどんどん進化しますので、同じ組み合わせが使えることは珍しくなってきています。

ちなみにお客様のシステムを設計する機会が多いわたしは、こんな流れで検討します。

1. 構成要素全体を俯瞰したうえで、調査が必要な技術や製品、ポイントを整理する
    * やみくもに調べものしないように
    * 経験あるアーキテクトは実績ある組み合わせや落とし穴を多くストックしているので、ここが早い
2. ベンダの公式資料を確認する
    * 「この使い方を推奨/サポートしています」と明記されていれば安心
    * でも星の数ほどある技術や製品との組み合わせがすべて網羅されているわけではない
    * 不明確なら早めに問い合わせる
3. ベンダが運営しているコミュニティ上の情報を確認する
    * ベンダの正式見解ではない場合もあるが、その製品を担当する社員が書いている情報には信ぴょう性がある
4. コミュニティや有識者の情報を確認する
    * OSSでは特に
    * 専門性を感じるサイト、人はリストしておく
5. 動かす
    * やっぱり動かしてみないと
6. 提案する
    * リスクがあれば明示します
7. 問題なければ実績になる、問題があればリカバリする
    * 提案しっぱなしにせずフォローすることで、自信とパターンが増える
    * 次の案件で活きる
    
いまのわたしの課題は４、5です。特にOSS案件。AzureはOSSとの組み合わせを推進していて、ここ半年でぐっと情報増えたのですが、まだ物足りません。断片的な情報を集め、仮説を立て、動かす機会が多い。なので、5を増やして、4の提供者側にならんとなぁ、と。

## Linux on AzureでDisk IO性能を確保する方法
さて今回の主題です。

結論: Linux on AzureでDisk IOを最大化するには、MDによるストライピングがおすすめ。いくつかパラメータを意識する。

Linux on AzureでDisk IO性能を必要とする案件がありました。検討したアイデアは、SSDを採用したPremium Storageを複数束ねてのストライピングです。Premium Storageはディスクあたり5,000IOPSを期待できます。でも、それで足りない恐れがありました。なので複数並べて平行アクセスし、性能を稼ぐ作戦です。

サーバ側でのソフトウェアストライピングは古くからあるテクニックで、ハードの能力でブン殴れそうなハイエンドUnixサーバとハイエンドディスクアレイを組み合わせた案件でも、匠の技として使われています。キャッシュやアレイコントローラ頼りではなく、明示的にアクセスを分散することで性能を確保することができます。

Linuxで使える代表的なストライプ実装は、LVMとMD。

ではAzure上でどちらがを選択すべきでしょう。この案件では性能が優先事項です。わたしはその時点で判断材料を持っていませんでした。要調査。この絞り込みまでが前半ポエムの1です。

前半ポエムの2、3はググ、もといBing力が試される段階です。わたしは以下の情報にたどり着きました。

["Configure Software RAID on Linux"](https://azure.microsoft.com/en-us/documentation/articles/virtual-machines-linux-configure-raid/)

["Premium Storage: Azure 仮想マシン ワークロード向けの高パフォーマンス ストレージ"](https://azure.microsoft.com/ja-jp/documentation/articles/storage-premium-storage-preview-portal/#premium-storage)

["Azure Storage secrets and Linux I/O optimizations"](http://blogs.msdn.com/b/igorpag/archive/2014/10/23/azure-storage-secrets-and-linux-i-o-optimizations.aspx)

得られた情報の中で大事なのは、

* 公式ドキュメントで
    * LVMではなくMDを使った構成例が紹介されている
* マイクロソフトがホストするブログ(MSDN)で、エキスパートが
    * LVMと比較したうえで、MDをすすめている
    * MDのChunkサイズについて推奨値を紹介している
    * そのほか、ファイルシステムやスケジューラに関する有益な情報あり

なるほど。わたしのこの時点での方針はこうです。

* LVMを使う必然性はないため、MDに絞る
    * LVMのほうが機能豊富だが、目的はストライピングだけであるため、シンプルなほうを
    * 物理障害対策はAzureに任せる (3コピー)
* MDのChunkをデフォルトの512KBから64KBに変更する
* Premium StorageのキャッシュはReadOnly or Noneにする予定であるため、ファイルシステムのバリアを無効にする

上記シナリオで、ディスク当たり5,000IOPS、ストライプ数に比例した性能が実際出れば提案価値あり、ということになります。
ですが、ズバリな実績値が見つからない。ダラダラ探すのは時間の無駄。これは自分でやるしかない。

構成手順は前述のリンク先にありますが、ポイントを抜き出します。OS=Ubuntu、ファイルシステム=ext4の場合です。

MDでストライプを作る際、チャンクを64KBに変更します。

    sudo mdadm --create /dev/md127 --level 0 --raid-devices 2  /dev/sdc1 /dev/sdd1 -c 64k
    
マウント時にバリアを無効にします。
 
    sudo mount /dev/md127 /mnt -o barrier=0
    
以下、Premium Storage(P30)をMDで2つ束ねたストライプにfioを実行した結果です。

* 100% Random Read
* キャッシュを無効にするため、Premium StorageのキャッシュはNone、fio側もdirect=1
* ブロックサイズは小さめの値が欲しかったので、1K


    randread: (g=0): rw=randread, bs=1K-1K/1K-1K/1K-1K, ioengine=libaio, iodepth=32
    fio-2.1.3
    Starting 1 process

    randread: (groupid=0, jobs=1): err= 0: pid=9193: Tue Jan 26 05:48:09 2016
      read : io=102400KB, bw=9912.9KB/s, iops=9912, runt= 10330msec
    [snip]

2本束ねて9,912IOPS。1本あたり5,000IOPS。ほぼ期待値。
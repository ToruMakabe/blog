+++
Categories = ["Azure"]
Tags = ["Azure", "Linux", "Blob"]
date = "2016-04-21T21:30:00+09:00"
title = "Azure Linux VMのディスク利用料節約Tips"

+++

## 定義領域全てが課金されるわけではありません
AzureのIaaSでは、VMに接続するディスクとしてAzure StorageのPage Blobを使います。Page Blobは作成時に容量を定義しますが、課金対象となるのは、実際に書き込んだ領域分のみです。たとえば10GBytesのVHD Page Blobを作ったとしても、1GBytesしか書き込んでいなければ、課金対象は1GBytesです。

[Understanding Windows Azure Storage Billing – Bandwidth, Transactions, and Capacity](https://blogs.msdn.microsoft.com/windowsazurestorage/2010/07/08/understanding-windows-azure-storage-billing-bandwidth-transactions-and-capacity/)
    
## 書き込み方はOSやファイルシステム次第
じゃあ、OSなりファイルシステムが、実際にどのタイミングでディスクに書き込むのか、気になりますね。実データの他に管理情報、メタデータがあるので、特徴があるはずです。Linuxで検証してみましょう。

* RHEL 7.2 on Azure
* XFS & Ext4
* 10GbytesのPage Blobの上にファイルシステムを作成
* mkfsはデフォルト
* mountはデフォルトとdiscardオプションありの2パターン
* MD、LVM構成にしない
* 以下のタイミングで課金対象容量を確認
    * Page BlobのVMアタッチ時
    * ファイルシステム作成時
    * マウント時
    * 約5GBytesのデータ書き込み時 (ddで/dev/zeroをbs=1M、count=5000で書き込み)
    * 5Gbytesのファイル削除時

課金対象容量は、以下のPowerShellで取得します。リファレンスは[ここ](https://gallery.technet.microsoft.com/scriptcenter/Get-Billable-Size-of-32175802)。

    $Blob = Get-AzureStorageBlob yourDataDisk.vhd -Container vhds -Context $Ctx

    $blobSizeInBytes = 124 + $Blob.Name.Length * 2
 
    $metadataEnumerator = $Blob.ICloudBlob.Metadata.GetEnumerator()
    while ($metadataEnumerator.MoveNext())
    {
        $blobSizeInBytes += 3 + $metadataEnumerator.Current.Key.Length + $metadataEnumerator.Current.Value.Length
    }

    $Blob.ICloudBlob.GetPageRanges() | 
        ForEach-Object { $blobSizeInBytes += 12 + $_.EndOffset - $_.StartOffset }

    return $blobSizeInBytes

ストレージコンテキストの作り方は[ここ](https://azure.microsoft.com/ja-jp/documentation/articles/storage-powershell-guide-full/)を参考にしてください。


## 結果
### XFS
|　確認タイミング　|　課金対象容量(Bytes)　|
|  :-----------  |  ------------:  |
|Page BlobのVMアタッチ時|960|
|ファイルシステム作成時|10,791,949|
|マウント時|10,791,949|
|5GBytesのデータ書き込み時|5,253,590,051|
|5Gbytesのファイル削除時|5,253,590,051|
|5Gbytesのファイル削除時 (discard)|10,710,029|

### Ext4
|　確認タイミング　|　課金対象容量(Bytes)　|
|  :-----------  |  ------------:  |
|Page BlobのVMアタッチ時|960|
|ファイルシステム作成時|138,683,592|
|マウント時|306,451,689|
|5GBytesのデータ書き込み時|5,549,470,887|
|5Gbytesのファイル削除時|5,549,470,887|
|5Gbytesのファイル削除時 (discard)|306,586,780|


この結果から、以下のことがわかります。

* 10GBytesのBlobを作成しても、全てが課金対象ではない
* 当然だが、ファイルシステムによってメタデータの書き方が違う、よって書き込み容量も異なる
* discardオプションなしでマウントすると、ファイルを消しても課金対象容量は減らない
    * OSがディスクに"消した"と伝えないから
    * discardオプションにてSCSI UNMAPがディスクに伝えられ、領域は解放される(課金対象容量も減る)
    * discardオプションはリアルタイムであるため便利。でも性能影響があるため、実運用ではバッチ適用(fstrim)が[おすすめ](https://access.redhat.com/documentation/ja-JP/Red_Hat_Enterprise_Linux/7/html/Storage_Administration_Guide/ch02s05.html)

    
知っているとコスト削減に役立つTipsでした。ぜひ運用前には、利用予定のファイルシステムやオプションで、事前に検証してみてください。
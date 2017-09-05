+++
Categories = ["Azure"]
Tags = ["Azure", "Blob", "EventGrid", "Functions"]
date = "2017-09-05T12:00:00+09:00"
title = "Azure Event GridでBlobイベントを拾う"

+++

## Event GridがBlobに対応
Event GridがBlobのイベントを拾えるように[なりました](https://azure.microsoft.com/en-us/blog/announcing-azure-blob-storage-events-preview/)。まだ申請が必要なプライベートプレビュー段階ですが、使い勝手の良いサービスに育つ予感がします。このたび検証する機会があったので、共有を。

プレビュー中なので、今後仕様が変わるかもしれないこと、不具合やメンテナンス作業の可能性などは、ご承知おきください。

## Event GridがBlobに対応して何がうれしいか
Event Gridは、Azureで発生した様々なイベントを検知してWebhookで通知するサービスです。カスタムトピックも作成できます。

イベントの発生元をPublisherと呼びますが、このたびPublisherとしてAzureのBlobがサポートされました。Blobの作成、削除イベントを検知し、Event GridがWebhookで通知します。通知先はHandlerと呼びます。Publisherとそこで拾うイベント、Handlerを紐づけるのがSubscriptionです。Subcriptionにはフィルタも定義できます。

![コンセプト](https://azurecomcdn.azureedge.net/mediahandler/acomblog/media/Default/blog/ff3644c9-58ab-4729-8939-66a83ab0605d.png "Concept")

Event Gridに期待する理由はいくつかあります。

* フィルタ
  * 特定のBlobコンテナーにあるjpegファイルのみで発火させる、なんてことができます
* 信頼性
  * リトライ機能があるので、Handlerが一時的に黙ってしまっても対応できます
* スケールと高スループット
  * [Azure Functions Blobトリガー](https://docs.microsoft.com/ja-jp/azure/azure-functions/functions-bindings-storage-blob#blob-storage-triggers-and-bindings)のようにHandler側で定期的にスキャンする必要がありません。これまではファイル数が多いとつらかった
  * 具体的な数値はプレビュー後に期待しましょう
* ファンアウト
  * ひとつのイベントを複数のHandlerに紐づけられます
* Azureの外やサードパーティーとの連携
  * Webhookでシンプルにできます

## 前提条件

* Publisherに設定できるストレージアカウントはBlobストレージアカウントのみです。汎用ストレージアカウントは対応していません
* 現時点ではWest Central USリージョンのみで提供しています
* プライベートプレビューは申請が必要です

Azure CLIの下記コマンドでプレビューに申請できます。
```
az provider register --namespace  Microsoft.EventGrid
az feature register --name storageEventSubscriptions --namespace Microsoft.EventGrid
```

以下のコマンドで確認し、statusが"Registered"であれば使えます。
```
az feature show --name storageEventSubscriptions --namespace Microsoft.EventGrid
```

## 使い方
ストレージアカウントの作成からSubscription作成までの流れを追ってみましょう。

リソースグループを作ります。
```
$ az group create -n blobeventpoc-rg -l westcentralus
```

Blobストレージアカウントを作ります。
```
$ az storage account create -n blobeventpoc01 -l westcentralus -g blobeventpoc-rg --sku Standard_LRS --kind BlobStorage --access-tier Hot
```

ではいよいよEvent GridのSubscriptionを作ります。
```
$ az eventgrid resource event-subscription create --endpoint https://requestb.in/y4jgj2x0 -n blobeventpocsub-jpg --prov
ider-namespace Microsoft.Storage --resource-type storageAccounts --included-event-types Microsoft.Storage.BlobCreated
-g blobeventpoc-rg --resource-name blobeventpoc01 --subject-ends-with jpg
```
以下はパラメーターの補足です。

* --endpoint
  * Handlerのエンドポイントを指定します。ここではテストのために[RequestBin](https://requestb.in/)に作ったエンドポイントを指定します
* --included-event-types
  * イベントの種類をフィルタします。Blobの削除イベントは不要で、作成のみ拾いたいため、Microsoft.Storage.BlobCreatedを指定します
* --subject-ends-with
  * 対象ファイルをフィルタします。Blob名の末尾文字列がjpgであるBlobのみイベントの対象にしました

では作成したストレージアカウントにBlobコンテナーを作成し、jpgファイルを置いてみましょう。テストには[Azure Storage Explorer](https://azure.microsoft.com/ja-jp/features/storage-explorer/)が便利です。

RequestBinにWebhookが飛び、中身を見られます。スキーマの確認は[こちら](https://docs.microsoft.com/en-us/azure/storage/blobs/storage-blob-event-overview#event-schema)から。
```
[{
  "topic": "/subscriptions/xxxxx-xxxxx-xxxxx-xxxxx/resourceGroups/blobeventpoc-rg/providers/Microsoft.Storage/storageAccounts/blobeventpoc01",
  "subject": "/blobServices/default/containers/images/blobs/handsomeyoungman.jpg",
  "eventType": "Microsoft.Storage.BlobCreated",
  "eventTime": "2017-09-02T02:25:15.2635962Z",
  "id": "f3ff6b96-001e-001d-6e92-23bdea0684d2",
  "data": {
    "api": "PutBlob",
    "clientRequestId": "f3cab560-8f85-11e7-bad1-53b58c70ab53",
    "requestId": "f3ff6b96-001e-001d-6e92-23bdea000000",
    "eTag": "0x8D4F1A9D8A6703A",
    "contentType": "image/jpeg",
    "contentLength": 42497,
    "blobType": "BlockBlob",
    "url": "https://blobeventpoc01.blob.core.windows.net/images/handsomeyoungman.jpg",
    "sequencer": "0000000000000BAB0000000000060986",
    "storageDiagnostics": {
      "batchId": "f3a538cf-5b88-4bbf-908a-20a37c65e238"
    }
  }
}]
```

.jpgだけじゃなくて.jpegも使われるかもしれませんね。ということで、エンドポイントが同じでフィルタ定義を変えたSubscriptionを追加します。--subject-ends-withをjpegとします。
```
$ az eventgrid resource event-subscription create --endpoint https://requestb.in/y0jbj1y0 -n blobeventpocsub-jpeg --pro
vider-namespace Microsoft.Storage --resource-type storageAccounts --included-event-types Microsoft.Storage.BlobCreated -
g blobeventpoc-rg --resource-name blobeventpoc01 --subject-ends-with jpeg
```

すると、拡張子.jpegのファイルをアップロードしても発火しました。
```
[{
  "topic": "/subscriptions/xxxxx-xxxxx-xxxxx-xxxxx/resourceGroups/blobeventpoc-rg/providers/Microsoft.Storage/storageAccounts/blobeventpoc01",
  "subject": "/blobServices/default/containers/images/blobs/handsomeyoungman.jpeg",
  "eventType": "Microsoft.Storage.BlobCreated",
  "eventTime": "2017-09-02T02:36:33.827967Z",
  "id": "e8b036ee-001e-00e7-4994-23740d06225b",
  "data": {
    "api": "PutBlob",
    "clientRequestId": "883ff7e0-8f87-11e7-bad1-53b58c70ab53",
    "requestId": "e8b036ee-001e-00e7-4994-23740d000000",
    "eTag": "0x8D4F1AB6D1B24F6",
    "contentType": "image/jpeg",
    "contentLength": 42497,
    "blobType": "BlockBlob",
    "url": "https://blobeventpoc01.blob.core.windows.net/images/handsomeyoungman.jpeg",
    "sequencer": "0000000000000BAB0000000000060D42",
    "storageDiagnostics": {
      "batchId": "9ec5c091-061d-4111-ad82-52d9803ce373"
    }
  }
}]
```

## Azure Functionsにイメージリサイズファンクションを作って連携してみる
Gvent Grid側の動きが確認できたので、サンプルアプリを作って検証してみましょう。Azure Functionsに画像ファイルのサイズを変えるHandlerアプリを作ってみます。

### 概要
当初想定したのは、ひとつのファンクションで、トリガーはEventGrid、入出力バインドにBlob、という作りでした。ですが、設計を変えました。

![Bindings](https://raw.githubusercontent.com/ToruMakabe/Images/master/blobevent-function-bindings.png "Bindings")

Using [Azure Functions Bindings Visualizer](https://functions-visualizer.azurewebsites.net/)

その理由はEvent Grid Blobイベントのペイロードです。Blobファイル名がURLで渡されます。Azure FunctionsのBlob入出力バインド属性、"path"にURLは使えません。使えるのはコンテナー名+ファイル名です。

入出力バインドを使わず、アプリのロジック内でStorage SDKを使って入出力してもいいのですが、Azure Functionsの魅力のひとつは宣言的にトリガーとバインドを定義し、アプリをシンプルに書けることなので、あまりやりたくないです。

そこでイベントを受けてファイル名を取り出してQueueに入れるファンクションと、そのQueueをトリガーに画像をリサイズするファンクションに分けました。

なお、この悩みはAzureの開発チームも認識しており、Functons側で対応する方針とのことです。

### Handler
C#(csx)で、Event GridからのWebhookを受けるHandlerを作ります。PublisherがBlobの場合、ペイロードにBlobのURLが入っていますので、そこからファイル名を抽出します。そのファイル名をQueueに送ります。ファンクション名はBlobEventHandlerとしました。

[run.csx]
```
#r "Newtonsoft.json"
using Microsoft.Azure.WebJobs.Extensions.EventGrid;

public static void Run(EventGridEvent eventGridEvent, out string outputQueueItem, TraceWriter log)
{
    log.Info(eventGridEvent.Data["url"].ToString());

    string imageUrl = eventGridEvent.Data["url"].ToString();
    outputQueueItem = System.IO.Path.GetFileName(imageUrl);
}
```

Event GridのWebJobs拡張向けパッケージを指定します。

[project.json]
```
{
"frameworks": {
  "net46":{
    "dependencies": {
      "Microsoft.Azure.WebJobs.Extensions.EventGrid": "1.0.0-beta1-10006"
    }
  }
 }
}
```

トリガーとバインドは以下の通りです。

[function.json]
```
{
  "bindings": [
    {
      "type": "eventGridTrigger",
      "name": "eventGridEvent",
      "direction": "in"
    },
    {
      "type": "queue",
      "name": "outputQueueItem",
      "queueName": "imagefilename",
      "connection": "AzureWebJobsStorage",
      "direction": "out"
    }
  ],
  "disabled": false
}
```

### Resizer
Queueをトリガーに、Blobから画像ファイルを取り出し、縮小、出力するファンクションを作ります。ファンクション名はResizerとしました。

[run.csx]
```
using ImageResizer;

public static void Run(string myQueueItem, Stream inputBlob, Stream outputBlob, TraceWriter log)
{
  var imageBuilder = ImageResizer.ImageBuilder.Current;
  var size = imageDimensionsTable[ImageSize.Small];

  imageBuilder.Build(inputBlob, outputBlob,
    new ResizeSettings(size.Item1, size.Item2, FitMode.Max, null), false);

}

public enum ImageSize
{
  Small
}

private static Dictionary<ImageSize, Tuple<int, int>> imageDimensionsTable = new Dictionary<ImageSize, Tuple<int, int>>()
{
  { ImageSize.Small,      Tuple.Create(100, 100) }
};
```

ImageResizerのパッケージを指定します。

[project.json]
```
{
"frameworks": {
  "net46":{
    "dependencies": {
      "ImageResizer": "4.1.9"
    }
  }
 }
}
```

トリガーとバインドは以下の通りです。{QueueTrigger}メタデータで、QueueのペイロードをBlobのpathに使います。また、画像を保存するBlobストレージアカウントの接続文字列は、環境変数BLOB_IMAGESへ事前に設定しています。なお、リサイズ後の画像を格納するBlobコンテナーは、"images-s"として別途作成しました。コンテナー"images"をイベントの発火対象コンテナーとして、Subscriptionにフィルタを定義したいからです。

[function.json]
```
{
  "bindings": [
    {
      "name": "myQueueItem",
      "type": "queueTrigger",
      "direction": "in",
      "queueName": "imagefilename",
      "connection": "AzureWebJobsStorage"
    },
    {
      "name": "inputBlob",
      "type": "blob",
      "path": "images/{QueueTrigger}",
      "connection": "BLOB_IMAGES",
      "direction": "in"
    },
    {
      "name": "outputBlob",
      "type": "blob",
      "path": "images-s/{QueueTrigger}",
      "connection": "BLOB_IMAGES",
      "direction": "out"
    }
  ],
  "disabled": false
}
```

Handlerの準備が整いました。最後にEvent GridのSubscriptionを作成します。トークン付きのエンドポイントは、ポータルの[統合]で確認できます。

```
$ az eventgrid resource event-subscription create --endpoint "https://blobeventpoc.azurewebsites.net/admin/exte
nsions/EventGridExtensionConfig?functionName=BlobEventHandler&code=tokenTOKEN1234567890==" -n blobeventpocsub-jpg --provider-namespace Microsoft.Storage --resource-type storageAccounts --included-event-types "Microsoft.Storage.BlobCreated" -g blobeventpoc-rg --resource-name blobeventpoc01 --subject-begins-with "/blobServices/default/containers/images/"  --subject-ends-with jpg
```

これで、コンテナー"images"にjpgファイルがアップロードされると、コンテナー"images-s"に、リサイズされた同じファイル名の画像ファイルが出来上がります。
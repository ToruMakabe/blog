+++
Categories = ["Azure"]
Tags = ["Azure", "Golang", "Storage"]
date = "2017-11-28T08:45:00+09:00"
title = "Azure Blob アップローダーをGoで書いた、そしてその理由"

+++

## Azure Blob アップローダーをGoで書いた
ふたつほど理由があり、GolangでAzure Blobのファイルアップローダーを書きました。

## ひとつめの理由: SDKが新しくなったから
最近公式ブログで[紹介された](https://azure.microsoft.com/en-us/blog/preview-the-new-azure-storage-sdk-for-go-storage-sdks-roadmap/)通り、Azure Storage SDK for Goが再設計され、プレビューが始まりました。GoはDockerやKubernetes、Terraformなど最近話題のプラットフォームやツールを書くのに使われており、ユーザーも増えています。再設計してもっと使いやすくしてちょ、という要望が多かったのも、うなずけます。

ということで、新しいSDKで書いてみたかった、というのがひとつめの理由です。ローカルにあるファイルを読んでBlobにアップロードするコードは、こんな感じ。

```
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/url"
	"os"

	"github.com/Azure/azure-storage-blob-go/2016-05-31/azblob"
)

var (
	accountName    string
	accountKey     string
	containerName  string
	fileName       string
	blockSize      int64
	blockSizeBytes int64
)

func init() {
	flag.StringVar(&accountName, "account-name", "", "(Required) Storage Account Name")
	flag.StringVar(&accountKey, "account-key", "", "(Required) Storage Account Key")
	flag.StringVar(&containerName, "c", "", "(Required - short option) Blob Container Name")
	flag.StringVar(&containerName, "container-name", "", "(Required) Blob Container Name")
	flag.StringVar(&fileName, "f", "", "(Required - short option) Upload filename")
	flag.StringVar(&fileName, "file", "", "(Required) Upload filename")
	flag.Int64Var(&blockSize, "b", 4, "(Optional - short option) Blob Blocksize (MB) - From 1 to 100. Max filesize depends on this value. Max filesize = Blocksize * 50,000 blocks")
	flag.Int64Var(&blockSize, "blocksize", 4, "(Optional) Blob Blocksize (MB) - From 1 to 100. Max filesize depends on this value. Max filesize = Blocksize * 50,000 blocks")
	flag.Parse()

	if (blockSize < 1) || (blockSize) > 100 {
		fmt.Println("Blocksize must be from 1MB to 100MB")
		os.Exit(1)
	}
	blockSizeBytes = blockSize * 1024 * 1024
}

func main() {
	file, err := os.Open(fileName)
	if err != nil {
		log.Fatal(err)
	}
	defer file.Close()
	fileSize, err := file.Stat()
	if err != nil {
		log.Fatal(err)
	}

	u, _ := url.Parse(fmt.Sprintf("https://%s.blob.core.windows.net/%s/%s", accountName, containerName, fileName))
	blockBlobURL := azblob.NewBlockBlobURL(*u, azblob.NewPipeline(azblob.NewSharedKeyCredential(accountName, accountKey), azblob.PipelineOptions{}))

	ctx := context.Background()

	fmt.Println("Uploading block blob...")
	putBlockList, err := azblob.UploadStreamToBlockBlob(ctx, file, fileSize.Size(), blockBlobURL,
		azblob.UploadStreamToBlockBlobOptions{
			BlockSize: blockSizeBytes,
			Progress: func(bytesTransferred int64) {
				fmt.Printf("Uploaded %d of %d bytes.\n", bytesTransferred, fileSize.Size())
			},
		})
	if err != nil {
		log.Fatal(err)
	}
	_ = putBlockList // Avoid compiler's "declared and not used" error

	fmt.Println("Done")
}
```

以前のSDKと比較し、スッキリ書けるようになりました。進行状況もPipelineパッケージを使って、楽に取れるようになっています。ブロック分割のロジックを書く必要もなくなりました。ブロックサイズを指定すればOK。

ちなみにファイルサイズがブロックサイズで割り切れると最終ブロックの転送がエラーになるバグを見つけたのですが、[修正してもらった](https://github.com/Azure/azure-storage-blob-go/issues/8)ので、次のリリースでは解決していると思います。

## ふたつめの理由: レガシー対応
Blobのアップロードが目的であれば、Azure CLIをインストールすればOK。以上。なのですが、残念ながらそれができないケースがあります。

たとえば。Azure CLI(2.0)はPythonで書かれています。なので、Pythonのバージョンや依存パッケージの兼ね合いで、「ちょっとそれウチのサーバーに入れるの？汚さないでくれる？ウチはPython2.6よ」と苦い顔をされることが、あるんですね。気持ちはわかります。立場の数だけ正義があります。Docker?その1歩半くらい前の話です。

ですが、オンプレのシステムからクラウドにデータをアップロードして処理したい、なんていうニーズが急増している昨今、あきらめたくないわけであります。どうにか既存環境に影響なく入れられないものかと。そこでシングルバイナリーを作って、ポンと置いて、動かせるGoは尊いわけです。

ファイルのアップロードだけでなく、Azureにちょっとした処理を任せたい、でもそれはいじりづらいシステムの上なのねん、って話は、結構多いんですよね。ということでシングルバイナリーを作って、ポンと置いて、動かせるGoは尊いわけです。大事なことなので2回書きました。

C#やNode、Python SDKと比較してGoのそれはまだ物足りないところも多いわけですが、今後注目ということで地道に盛り上がっていこうと思います。
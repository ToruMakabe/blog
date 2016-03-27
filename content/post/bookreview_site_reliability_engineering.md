+++
Categories = ["Book"]
Tags = ["Book", "Ops", "Google"]
date = "2016-03-27T20:00:00+09:00"
title = "書評: Site Reliability Engineering"

+++

## 英語だけどぜひ読んでほしい
**[Site Reliability Engineering: How Google Runs Production Systems](http://www.amazon.co.jp/Site-Reliability-Engineering-Production-Systems-ebook/dp/B01DCPXKZ6/ref=tmm_kin_swatch_0?_encoding=UTF8&qid=1459069692&sr=8-1)**

参考になったのでご紹介。Googleのインフラ/Ops系技術チームの働き方や考え方を題材にした本です。SREの情報は断片的に知っていたのですが、まとめて読むと違いますね。背景やストーリーがあって、理解しやすいです。

共感できるネタがどんどん繰り出されるので、一気読みしました。読み込みが浅いところもあったので、改めて読む予定。

以下、印象に残ったこと。

* Site Reliability Engineering teamは、インフラ/Ops担当であるが、Unix内部やネットワークなどインフラの知見を持つソフトウェアエンジニアの集団。自分たちのオペレーションを効率的に、迅速に、確実にするために、コードを書く。

* インシデント対応、問い合わせ対応、手作業は仕事の50%に収まるように調整する。残りの時間は自分たちの仕事をより良く、楽にするためにコードを書く。

* 日々のリアクティブな活動に忙殺されるインフラ/Ops担当はどうしても減点評価になりがちだが、仕事の半分がプロアクティブな活動であり、成果を加点評価できる。昇格、昇給の根拠になりやすい。

* アプリ/製品チームとSREチームは"Error Budget"を定義、共有する。これは四半期ごとに定義される、サービスレベル目標である。ユーザがサービスを使えなくなると、その時間が、このError Budgetから取り崩されていく。Budgetが残り少なくなると、リスクを伴うデプロイなどは控える。

* インフラ/Ops担当は「サービスを少しでもダウンさせたら悪」となりがちだが、サービスごとにアプリ/製品チームとSREチームがError Budgetを共有することで、利害関係を一致できる。

* Error Budgetの大きさはサービスごとに異なり、定義は製品チームの責任。当然Error Budgetが少ない = サービスレベルが高い = コストがかかる ので、製品チームはいたずらに高いサービスレベルを定義しない。Google Apps for WorkとYoutubeのError Budgetは異なる。Appsはサービスレベル重視であり、Youtubeは迅速で頻繁な機能追加を重視する。

* SLA違反など、重大な障害では"Postmortem(過激だが死体解剖)"を作成し、失敗から学ぶ。客観的に、建設的に。誰かや何かを責めるためにやるわけではない。マサカリ投げない。

* 他の産業から学ぶ。製造業のビジネス継続プラン、国防のシミレーションや演習、通信業の輻輳対策など。

もう一回読んだら、また違う発見があるんじゃないかと。

## 自分ごととして読みたい
今後の働き方や所属組織に行き詰まりを感じているインフラ/Ops技術者に、参考になるネタが多いと思います。

DevOpsムーブメントが来るか来ないかという今、Opsとしてのスタンスを考え直すのにも、いいかもしれません。

もちろん、Googleの圧倒的物量、成長スピードゆえのミッションと働き方である事は否定しません。でも、自分とは無関係、と無視するにはもったいないです。

なお、このSREチーム、できてから10年以上たっているそうです。それだけ持続できるのには、何か本質的な価値があるのではないでしょうか。

オススメです。
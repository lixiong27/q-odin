# 小红书帖子bigsearch 请求参数 & 报文
```
{
    "source": "redbook",
    "taskType": "bigSearch",
    "businessType": "mkt_odin",
    "crawlCount": 5,
    "filterDuplicate": true,
    "priority": 2,
    "expireAt": "2035-01-01 00:00:00",
    "taskId": "xxx24",
    "param": {
        "filters": "[{\"tags\": [\"general\"], \"type\": \"sort_type\"}, {\"tags\": [\"普通笔记\"], \"type\": \"filter_note_type\"}, {\"tags\": [\"不限\"], \"type\": \"filter_note_time\"}, {\"tags\": [\"不限\"], \"type\": \"filter_note_range\"}, {\"tags\": [\"不限\"], \"type\": \"filter_pos_distance\"}]",
        "keyword":"梅梅儿（小个子女 生穿搭）"
    }
}
```
```
{
  "messageId": "260625.172908.10.88.169.163.30528.1159133",
  "subject": "push_content_crawl_mkt_odin_res_topic",
  "durable": true,
  "storeAtFailed": false,
  "successIfStoreOk": false,
  "tags": [],
  "attrs": {
    "qmq_expireTime": "1782380648059",
    "qmq_maxRetryNum": -1,
    "qmq_appCode": "h_crawl_scheduler",
    "qmq_env": "prod",
    "qmq_createTIme": "1782379748059",
    "qmq_traceContext": {
      "qscheduleTaskId": "260625.172908.10.88.105.124.25201.126415819_5_0"
    },
    "qmq_subEnv": "",
    "qmq_reliabilityLevel": "High",
    "qmq_traceId": "h_crawl_scheduler_260625.172908.10.88.169.163.30528.1138553_0",
    "body": {
      "taskId": "xxx24",
      "source": "redbook",
      "taskType": "bigSearch",
      "crawlerType": "magic_redbook_xcx_bigSearch",
      "failReason": null,
      "data": {
        "data": {
          "code": 0,
          "data": {
            "has_more": true,
            "items": [
              {
                "note_card": {
                  "cover": {
                    "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251728/69d114fcd4d71da307a45a4d7d9774d6/spectrum/1040g34o321msm0lp74105q6mb9r8bnv97o0fr98!nc_n_nwebp_prv_1",
                    "width": 500,
                    "url_default": "http://sns-webpic-qc.xhscdn.com/202606251728/d4c65df9b096b3ebeefe479910b24758/spectrum/1040g34o321msm0lp74105q6mb9r8bnv97o0fr98!nc_n_nwebp_mw_1",
                    "height": 667
                  },
                  "display_title": "身高160小个子春季穿搭｜这套公式真的显高",
                  "interact_info": {
                    "liked_count": "0",
                    "liked": false
                  },
                  "type": "normal",
                  "user": {
                    "user_id": "68d65a76000000002101dfe9",
                    "nick_name": "侠影飘零斩断情",
                    "avatar": "https://sns-avatar-qc.xhscdn.com/avatar/1040g2jo321hofu7u7o605q6mb9r8bnv9mbte9c8?imageView2/2/w/80/format/jpg"
                  },
                  "image_list": [
                    {
                      "width": 500,
                      "info_list": [
                        {
                          "image_scene": "WB_DFT",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251728/d4c65df9b096b3ebeefe479910b24758/spectrum/1040g34o321msm0lp74105q6mb9r8bnv97o0fr98!nc_n_nwebp_mw_1"
                        },
                        {
                          "image_scene": "WB_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251728/69d114fcd4d71da307a45a4d7d9774d6/spectrum/1040g34o321msm0lp74105q6mb9r8bnv97o0fr98!nc_n_nwebp_prv_1"
                        }
                      ],
                      "height": 667
                    }
                  ]
                },
                "model_type": "note",
                "id": "6a38d3d4000000000f02b532",
                "xsec_token": "ABbVDxWz44ZBQdYreYx-qy2ZuWjgQTqJhjTq4QooBNI14="
              }
            ]
          },
          "success": true
        },
        "pageNum": 1,
        "reachedBottom": false,
        "dataCount": 0,
        "totalCrawlCount": 0,
        "targetCount": 0
      },
      "statusCode": null
    },
    "qmq_receiveTime": 1782379748059,
    "qmq_isnewqmq": "true",
    "qmq_spanId": "1.1.1"
  },
  "newqmq": true,
  "bigMessage": false,
  "maxRetryNum": -1
}
```
# 小红书帖子detail 请求参数 & 报文
```
{
  "source": "redbook",
  "taskType": "detail",
  "businessType": "你的业务标识",//确定了告知@贾哲(抓取)即可
  "priority": 3,
  "expireAt": "2026-06-15 23:59:59",//过期时间晚于当前
  "taskId": "你的唯一任务ID",
  "param": {
    "noteId": "6712345678abcdef01234567"
    "xsecToken":"xxxxxx"#可选 如果填了就走小程序渠道，不填走app渠道
  }
}
```
```
{
  "source": "redbook",
  "taskType": "detail",
  "businessType": "你的业务标识",//确定了告知@贾哲(抓取)即可
  "priority": 3,
  "expireAt": "2026-06-15 23:59:59",//过期时间晚于当前
  "taskId": "你的唯一任务ID",
  "param": {
    "noteId": "6712345678abcdef01234567"
    "xsecToken":"xxxxxx"#可选 如果填了就走小程序渠道，不填走app渠道
  }
}
```
```
{
  "messageId": "260625.171940.10.88.169.163.30528.1154457",
  "subject": "push_content_crawl_mkt_odin_res_topic",
  "durable": true,
  "storeAtFailed": false,
  "successIfStoreOk": false,
  "tags": [],
  "attrs": {
    "qmq_expireTime": "1782380080125",
    "qmq_maxRetryNum": -1,
    "qmq_appCode": "h_crawl_scheduler",
    "qmq_env": "prod",
    "qmq_createTIme": "1782379180125",
    "qmq_traceContext": {
      "qscheduleTaskId": "260625.171940.10.88.101.160.7447.132943190_30_1"
    },
    "qmq_subEnv": "",
    "qmq_reliabilityLevel": "High",
    "qmq_traceId": "h_crawl_scheduler_260625.171940.10.88.169.163.30528.1134710_0",
    "body": {
      "taskId": "xx23",
      "source": "redbook",
      "taskType": "detail",
      "crawlerType": "magic_redbook_xcx_detail",
      "failReason": null,
      "data": {
        "data": {
          "msg": "成功",
          "code": 0,
          "data": {
            "cards": [
              {
                "note_card": {
                  "note_id": "6a366131000000002101aa61",
                  "share_info": {
                    "un_share": false
                  },
                  "interact_info": {
                    "comment_count": "21",
                    "share_count": "1",
                    "liked_count": "84",
                    "collected_count": "52",
                    "sticky": false,
                    "collected": false,
                    "followed": false,
                    "liked": false,
                    "relation": "none"
                  },
                  "title": "三亚3天2晚旅游攻略🌴｜节奏松弛不赶路！",
                  "type": "normal",
                  "at_user_list": [],
                  "ip_location": "江苏",
                  "xsec_token": "ABP7J72CZ6lrbqRFIs9oxCkym4bL3aRJ3dtMSSoqZ9dNo=",
                  "last_update_time": 1781948722000,
                  "tag_list": [
                    {
                      "name": "三亚旅游攻略",
                      "id": "5bf11f0e9e1dec00019ed46e",
                      "type": "topic"
                    },
                    {
                      "name": "三亚3天2晚旅游",
                      "id": "68be32d80000000006034032",
                      "type": "topic"
                    },
                    {
                      "name": "三亚大东海拍照",
                      "id": "6511ea19000000000e006446",
                      "type": "topic"
                    },
                    {
                      "name": "三亚海上观音",
                      "id": "615fd6710000000001009644",
                      "type": "topic"
                    },
                    {
                      "name": "天涯海角",
                      "id": "5c45bdbf000000000d020d9c",
                      "type": "topic"
                    },
                    {
                      "name": "三亚美食",
                      "id": "5940f363805d8978fc583bed",
                      "type": "topic"
                    },
                    {
                      "name": "后安粉",
                      "id": "5d35ae6e000000000d0058cf",
                      "type": "topic"
                    },
                    {
                      "name": "醋小椰三亚湾店",
                      "id": "6a36606f00000000010326fe",
                      "type": "topic"
                    },
                    {
                      "name": "三亚椰子鸡糟粕醋",
                      "id": "67584d91000000000b024692",
                      "type": "topic"
                    },
                    {
                      "name": "海南旅行",
                      "id": "5be9321ea6da940001a959a4",
                      "type": "topic"
                    },
                    {
                      "name": "三亚吃喝玩乐",
                      "id": "5ecfc9f10000000001001f23",
                      "type": "topic"
                    }
                  ],
                  "time": 1781948721000,
                  "user": {
                    "user_id": "5e15586000000000010012c9",
                    "nick_name": "小小小提米。",
                    "avatar": "https://sns-avatar-qc.xhscdn.com/avatar/1040g2jo31jq4abdniul05nglb1g084m9h2d01ug",
                    "xsec_token": "ABtcbO0B2BEbuaW2b4cu8M6K5fQ-_NrHGyVbMoSHBLEFE="
                  },
                  "desc": "拍照点位、bi逛景点、地道美食都安排到位\n第1️⃣次来三亚照着玩就够啦\n\t\n📅行程安排\nDay1 ✈️抵达三亚｜入住大东海\n落地办理入住，建议住在大东海，地理位置居中，去往各个片区车程都比较方便。\n等到傍晚光线柔和时🌇去大东海海边打卡拍照，避开正午暴晒，拍完沿着海岸线走到三亚湾，顺路等候一场橘子海落日。\n晚餐安排三亚湾的醋小椰，一边吃火锅一边欣赏海景晚霞，氛围感直接拉🈵\n\t\nDay2🚗 西线一日游：南海观音→天涯海角\n早上早点出发前往南山文化旅游区\n打卡108米海上观音\n中午可以在景区吃素斋简餐\n下午游玩天涯海角，沿着海岸线漫步礁石沙滩\n傍晚返程市区，晚上逛逛夜市，品尝各类海南小吃。\n\t\nDay3 市区逛吃美食→返程\n早起打卡本地人早餐后安粉🍜依次打卡陵水酸粉、清补凉、糯叽叽特色小食，吃完采购伴手礼\n\t\n📸大东海出片机位\n▪️网红海景窗框🪟\n▪️沙滩粉色蝴蝶结+小花船\n▪️临海原木栈道、海上秋千\n▪️椰林步道\n\t\n✨拍照小tips\n最佳拍摄时间：上午10点前、下午4:30以后\n穿搭首选浅色长裙👗一定要做好防晒，备好帽子墨镜。\n\t\n🍜三亚美食合集\n▫️醋小椰·海南椰子鸡·糟粕醋\n▫️后安粉，抱罗粉\n▫️海南特色街边小食\n\t\n✔️陵水酸粉：酱汁酸辣浓郁！嗦粉爱好者必尝\n✔️椰奶清补凉：鲜果杂粮满满一碗！解暑🍧\n✔️椰子饭、斑斓煎堆：软糯香甜，自带椰香\n✔️芒果炒冰、榴莲炒冰：鲜果现炒，口感绵密顺滑\n\t\n#三亚旅游攻略 #三亚3天2晚旅游 #三亚大东海拍照 #三亚海上观音 #天涯海角 #三亚美食 #后安粉 #醋小椰三亚湾店 #三亚椰子鸡糟粕醋 #海南旅行 #三亚吃喝玩乐",
                  "image_list": [
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/d10a982d301c6019870b8ba13810ad0c/notes_pre_post/1040g3k8321kpdrvn7a705nglb1g084m9jlq6lmo!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7a705nglb1g084m9jlq6lmo",
                      "width": 2880,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/d10a982d301c6019870b8ba13810ad0c/notes_pre_post/1040g3k8321kpdrvn7a705nglb1g084m9jlq6lmo!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/1effdae090d424c9e9a86ccae132f5b2/notes_pre_post/1040g3k8321kpdrvn7a705nglb1g084m9jlq6lmo!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/1effdae090d424c9e9a86ccae132f5b2/notes_pre_post/1040g3k8321kpdrvn7a705nglb1g084m9jlq6lmo!mini_dtl_jpg",
                      "url": "",
                      "height": 3840
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/0bf79c77587a95e5c952c2e0170f3a80/notes_pre_post/1040g3k8321kpdrvn7a7g5nglb1g084m9tl8vog8!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7a7g5nglb1g084m9tl8vog8",
                      "width": 6037,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/0bf79c77587a95e5c952c2e0170f3a80/notes_pre_post/1040g3k8321kpdrvn7a7g5nglb1g084m9tl8vog8!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/6f1c90d9cdb0d31876552339ee1afa70/notes_pre_post/1040g3k8321kpdrvn7a7g5nglb1g084m9tl8vog8!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/6f1c90d9cdb0d31876552339ee1afa70/notes_pre_post/1040g3k8321kpdrvn7a7g5nglb1g084m9tl8vog8!mini_dtl_jpg",
                      "url": "",
                      "height": 8050
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/b086e85849a2f85123513660203ee69f/notes_pre_post/1040g3k8321kpdrvn7a805nglb1g084m9cubg22g!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7a805nglb1g084m9cubg22g",
                      "width": 2879,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/b086e85849a2f85123513660203ee69f/notes_pre_post/1040g3k8321kpdrvn7a805nglb1g084m9cubg22g!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/ca0b5ce52dd22cb4a6b6cf5ae6f536d3/notes_pre_post/1040g3k8321kpdrvn7a805nglb1g084m9cubg22g!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/ca0b5ce52dd22cb4a6b6cf5ae6f536d3/notes_pre_post/1040g3k8321kpdrvn7a805nglb1g084m9cubg22g!mini_dtl_jpg",
                      "url": "",
                      "height": 3840
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/39f39268a5d65f3972cc4fa320f00a0c/notes_pre_post/1040g3k8321kpdrvn7a8g5nglb1g084m9u8hf9t8!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7a8g5nglb1g084m9u8hf9t8",
                      "width": 2880,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/39f39268a5d65f3972cc4fa320f00a0c/notes_pre_post/1040g3k8321kpdrvn7a8g5nglb1g084m9u8hf9t8!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/c4246e33a5249a812e2e783e5d82b38a/notes_pre_post/1040g3k8321kpdrvn7a8g5nglb1g084m9u8hf9t8!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/c4246e33a5249a812e2e783e5d82b38a/notes_pre_post/1040g3k8321kpdrvn7a8g5nglb1g084m9u8hf9t8!mini_dtl_jpg",
                      "url": "",
                      "height": 3840
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/5aaac72c7212519a914368db63672c49/notes_pre_post/1040g3k8321kpdrvn7a905nglb1g084m9d8c8ao0!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7a905nglb1g084m9d8c8ao0",
                      "width": 2879,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/5aaac72c7212519a914368db63672c49/notes_pre_post/1040g3k8321kpdrvn7a905nglb1g084m9d8c8ao0!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/d267d27c9d13a7bfa63c86807f3ae756/notes_pre_post/1040g3k8321kpdrvn7a905nglb1g084m9d8c8ao0!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/d267d27c9d13a7bfa63c86807f3ae756/notes_pre_post/1040g3k8321kpdrvn7a905nglb1g084m9d8c8ao0!mini_dtl_jpg",
                      "url": "",
                      "height": 3840
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/5f7515a68e74df810206d0964c3d3120/1040g2sg321kpdrvm7ke05nglb1g084m93m53ai8!mini_prv_jpg",
                      "file_id": "1040g2sg321kpdrvm7ke05nglb1g084m93m53ai8",
                      "width": 1920,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/5f7515a68e74df810206d0964c3d3120/1040g2sg321kpdrvm7ke05nglb1g084m93m53ai8!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/cf4c29328690a1a65c504a0ee1e99412/1040g2sg321kpdrvm7ke05nglb1g084m93m53ai8!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/cf4c29328690a1a65c504a0ee1e99412/1040g2sg321kpdrvm7ke05nglb1g084m93m53ai8!mini_dtl_jpg",
                      "url": "",
                      "height": 2560
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/777a779ee9fb23446f61b239136d2a75/notes_pre_post/1040g3k8321kpdrvn7aa05nglb1g084m939ci6tg!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7aa05nglb1g084m939ci6tg",
                      "width": 6037,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/777a779ee9fb23446f61b239136d2a75/notes_pre_post/1040g3k8321kpdrvn7aa05nglb1g084m939ci6tg!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/7f621b5dd9761756fed47b1604938f8c/notes_pre_post/1040g3k8321kpdrvn7aa05nglb1g084m939ci6tg!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/7f621b5dd9761756fed47b1604938f8c/notes_pre_post/1040g3k8321kpdrvn7aa05nglb1g084m939ci6tg!mini_dtl_jpg",
                      "url": "",
                      "height": 8050
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/8ca7e5e70607e9e132c00a5ba22850b7/1040g2sg321kpdrvm7keg5nglb1g084m9140s5f8!mini_prv_jpg",
                      "file_id": "1040g2sg321kpdrvm7keg5nglb1g084m9140s5f8",
                      "width": 1920,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/8ca7e5e70607e9e132c00a5ba22850b7/1040g2sg321kpdrvm7keg5nglb1g084m9140s5f8!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/5924690afced38e60b6c244afbfdaf03/1040g2sg321kpdrvm7keg5nglb1g084m9140s5f8!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/5924690afced38e60b6c244afbfdaf03/1040g2sg321kpdrvm7keg5nglb1g084m9140s5f8!mini_dtl_jpg",
                      "url": "",
                      "height": 2560
                    },
                    {
                      "trace_id": "",
                      "url_pre": "http://sns-webpic-qc.xhscdn.com/202606251719/1b5c2c6044a1faee60238767533c64fd/notes_pre_post/1040g3k8321kpdrvn7ab05nglb1g084m93jk5r9g!mini_prv_jpg",
                      "file_id": "notes_pre_post/1040g3k8321kpdrvn7ab05nglb1g084m93jk5r9g",
                      "width": 2879,
                      "info_list": [
                        {
                          "image_scene": "MINPRO_PRV",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/1b5c2c6044a1faee60238767533c64fd/notes_pre_post/1040g3k8321kpdrvn7ab05nglb1g084m93jk5r9g!mini_prv_jpg"
                        },
                        {
                          "image_scene": "MINPRO_DTL",
                          "url": "http://sns-webpic-qc.xhscdn.com/202606251719/49256b2674526c6b5c3195cdea3fbaf8/notes_pre_post/1040g3k8321kpdrvn7ab05nglb1g084m93jk5r9g!mini_dtl_jpg"
                        }
                      ],
                      "url_default": "http://sns-webpic-qc.xhscdn.com/202606251719/49256b2674526c6b5c3195cdea3fbaf8/notes_pre_post/1040g3k8321kpdrvn7ab05nglb1g084m93jk5r9g!mini_dtl_jpg",
                      "url": "",
                      "height": 3840
                    }
                  ]
                },
                "model_type": "note",
                "ignore": false,
                "id": "6a366131000000002101aa61",
                "xsec_token": "ABP7J72CZ6lrbqRFIs9oxCkym4bL3aRJ3dtMSSoqZ9dNo="
              }
            ],
            "cursor_score": "",
            "current_time": 1782379175802
          },
          "success": true
        },
        "pageNum": 1,
        "reachedBottom": false,
        "dataCount": 0,
        "totalCrawlCount": 0,
        "targetCount": 0
      },
      "statusCode": null
    },
    "qmq_receiveTime": 1782379180125,
    "qmq_isnewqmq": "true",
    "qmq_spanId": "1.11.1"
  },
  "newqmq": true,
  "bigMessage": false,
  "maxRetryNum": -1
}
```
# 小红书帖子author 请求 & 报文
```
{
  "source": "redbook",
  "taskType": "userInfo",
  "businessType": "你的业务标识",
  "priority": 3,
  "expireAt": "2026-04-15 23:59:59",
  "taskId": "你的唯一任务ID",
  "param": {
    "userId": "5f1234567890abcdef012345"
  }
}
```

```
{
  "messageId": "260625.165150.10.88.169.156.14590.1159244",
  "subject": "push_content_crawl_mkt_odin_res_topic",
  "durable": true,
  "storeAtFailed": false,
  "successIfStoreOk": false,
  "tags": [],
  "attrs": {
    "qmq_expireTime": "1782378410115",
    "qmq_maxRetryNum": -1,
    "qmq_appCode": "h_crawl_scheduler",
    "qmq_env": "prod",
    "qmq_createTIme": "1782377510115",
    "qmq_traceContext": {
      "qscheduleTaskId": "260625.165150.10.88.101.160.7447.132904837_30_0"
    },
    "qmq_subEnv": "",
    "qmq_reliabilityLevel": "High",
    "qmq_traceId": "h_crawl_scheduler_260625.165150.10.88.169.156.14590.1126467_0",
    "body": {
      "taskId": "23",
      "source": "redbook",
      "taskType": "userInfo",
      "crawlerType": "redbook_adr_app_userInfo",
      "failReason": null,
      "data": {
        "data": {
          "data": {
            "desc": "分享日常穿搭",
            "collected_tags_num": 0,
            "share_link": "https://www.xiaohongshu.com/user/profile/61a39f950000000010005f17?xsec_token=YBLCEgqPbZS9Q2OjSm4vNJS4SogWEs3QuFOV-0kb-_qRk=&xsec_source=app_share",
            "share_info_v2": {
              "title": "@KK教穿搭的个人主页",
              "content": "粉丝: 8624\n获赞与收藏: 3.8万",
              "ecom_title": "KK教穿搭的店铺",
              "ecom_content": "快来KK教穿搭的店里逛逛！已有16人买过了！",
              "ecom_share_link": "https://www.xiaohongshu.com/user/profile/61a39f950000000010005f17?tab=goods&channelType=share_outside"
            },
            "avatar_like_status": false,
            "location": "中国  浙江  杭州",
            "default_collection_tab": "note",
            "blocked": false,
            "interactions": [
              {
                "is_private": true,
                "toast": "该用户已设置关注列表不可见",
                "type": "follows",
                "name": "关注",
                "count": 2
              },
              {
                "is_private": true,
                "toast": "该用户已设置粉丝列表不可见",
                "type": "fans",
                "name": "粉丝",
                "count": 8624
              },
              {
                "type": "interaction",
                "name": "获赞与收藏",
                "count": 37639,
                "is_private": false,
                "toast": ""
              }
            ],
            "customer_service_link": "xhsdiscover://rn/eva-seraph/seller/69c7f66373210b00155e05dc/chat?sellerId=69c7f66373210b00155e05dc&entry=1001",
            "remark_name": "",
            "location_jump": true,
            "identity_label_migrated": false,
            "block_view_from_user": false,
            "result": {
              "message": "success",
              "success": true,
              "code": 0
            },
            "tags": [
              {
                "icon": "http://ci.xiaohongshu.com/icons/user/gender-male-v1.png",
                "tag_type": "info"
              },
              {
                "name": "浙江杭州",
                "tag_type": "location"
              },
              {
                "name": "时尚博主",
                "tag_type": "profession"
              }
            ],
            "red_official_verify_type": 0,
            "recommend_info": "",
            "userid": "61a39f950000000010005f17",
            "identity_deeplink": "xhsdiscover://rn/app-settings/official/certification/details?type=2&user_id=61a39f950000000010005f17&is_mcn=false",
            "ip_location": "安徽",
            "user_role_type": 6,
            "is_login_user_pro_account": false,
            "fans": 8624,
            "level": {
              "number": 0,
              "image_link": ""
            },
            "collected_movie_num": 0,
            "collected_book_num": 0,
            "nickname": "KK教穿搭",
            "collected_poi_num": 0,
            "note_num_stat": {
              "posted": 160,
              "liked": 24300,
              "collected": 13339
            },
            "follows": 2,
            "liked": 24300,
            "user_desc_info": {
              "desc": "分享日常穿搭",
              "desc_at_users": [],
              "desc_with_placeholder": "分享日常穿搭",
              "desc_keywords_switch": true
            },
            "is_recommend_level_illegal": false,
            "nboards": 0,
            "collected_product_num": 0,
            "collected_brand_num": 0,
            "red_club_info": {
              "red_club": false,
              "red_club_level": 0,
              "red_club_url": "https://www.xiaohongshu.com/store/mc/landing",
              "redclubscore": 0
            },
            "avatar_pendant": {
              "current_user_pendant": false,
              "current_user_pet": false
            },
            "real_name_deep_target": 1,
            "imageb": "https://sns-avatar-qc.xhscdn.com/avatar/seller_69c801a979992c0001258cd4?imageView2/2/w/540/format/webp",
            "collected_notes_num": 1,
            "share_info": {
              "title": "KK教穿搭",
              "content": "分享日常穿搭",
              "store_link": "xhsdiscover://rn/lancer/shop-detail/69c7f66373210b00155e05dc"
            },
            "red_official_verify_content": "",
            "show_extra_info_button": false,
            "user_widget_switch": false,
            "mute_view_to_user": false,
            "banner_info": {
              "image": "https://sns-avatar-qc.xhscdn.com/user_banner/default/h30-b50.png?imageView2/2/w/540/format/jpg&ap=28&sc=USR_BG",
              "bg_color": "d9b4b5",
              "like_status": false
            },
            "fstatus": "none",
            "gender": 0,
            "recommend_info_icon": "",
            "red_official_verified": false,
            "desc_at_users": [],
            "collected": 13339,
            "red_id": "8062790348",
            "community_rule_url": "https://www.xiaohongshu.com/user/community-rule",
            "blocking": false,
            "hula_tabs": {
              "all_show_tab_config": [
                {
                  "tab_id": "note",
                  "tab_name": "笔记",
                  "tab_index_weight": 0
                },
                {
                  "tab_id": "collect",
                  "tab_name": "收藏",
                  "tab_index_weight": 10,
                  "is_show_lock": false
                },
                {
                  "tab_id": "goods_new",
                  "tab_name": "商品",
                  "tab_index_weight": 4
                }
              ],
              "tab_id_selected": "note"
            },
            "tab_visible": {
              "note": true,
              "collect": true,
              "like": false,
              "goods": false,
              "seed": true
            },
            "seller_info": {
              "tab_goods_name": "商品",
              "is_tab_goods_first": true,
              "can_process_coupon": true,
              "display_modules": {
                "official": true
              },
              "tab_goods_api_version": 2,
              "store_id": "69c7f66373210b00155e05dc",
              "tab_code_names": [
                "TRADE_COMMODITY_TAB",
                "TRADE_SELLER_INFO"
              ]
            },
            "buyer_info": {
              "tab_name": "选品",
              "choice_id": "137417343048268406",
              "extra_map": {
                "curationGoodsSearch": "true"
              }
            },
            "zhong_tong_bar_info": {
              "conversions": []
            },
            "images": "https://sns-avatar-qc.xhscdn.com/avatar/seller_69c801a979992c0001258cd4?imageView2/2/w/360/format/webp",
            "ndiscovery": 160,
            "tab_public": {
              "collection": true,
              "collection_note": true,
              "collection_board": true,
              "seed": true
            },
            "red_official_verify_base_info": "",
            "real_name_info": "",
            "sec_account_deeplink": "xhsdiscover://rn/accounts/account-detail?targetId=61a39f950000000010005f17&new_page_exp=1",
            "block_view_to_user": false
          },
          "code": 0,
          "success": true,
          "msg": "成功"
        }
      },
      "statusCode": null
    },
    "qmq_receiveTime": 1782377510115,
    "qmq_isnewqmq": "true",
    "qmq_spanId": "1.5.1"
  },
  "newqmq": true,
  "bigMessage": false,
  "maxRetryNum": -1
}
```
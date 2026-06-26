# 字段映射 & 回调报文对照

## 1. BigSearch → List 页回调字段提取

```
回调 data.data.data.items[]
  ├── id                        → note_id
  ├── xsec_token                → 透传给 detail 子任务
  ├── model_type                → "note"
  ├── note_card
  │   ├── display_title         → 标题（列表页用，完整标题在 detail 里）
  │   ├── type                  → "normal"(图文) / "video"(视频)
  │   ├── cover                 → 封面图（BigSearch 独立封面对象，可能与 image_list[0] 不同）
  │   │   ├── url_pre / url_default
  │   │   ├── width, height
  │   ├── image_list[]          → 图片列表（BigSearch 可能只返回首图，Detail 返回完整列表）
  │   │   ├── width, height
  │   │   ├── info_list[].url   → 各场景图片URL
  │   ├── interact_info
  │   │   ├── liked_count       → 点赞数
  │   │   └── liked
  │   └── user
  │       ├── user_id           → author_id（用于创建 author 子任务）
  │       ├── nick_name         → 作者昵称
  │       └── avatar            → 作者头像
```

### 判断逻辑：

```
note_card.type == "normal" && model_type == "note"
  → 图文帖，走新流程（创建 author + detail 子任务）

note_card.type == "video" && model_type == "note"
  → 视频，走原有流程（已有处理逻辑）
```

---

## 2. Detail 回调 → `redbook_note_post` 字段映射

| 表字段 | 报文路径 | 示例值 |
|--------|----------|--------|
| note_id | `cards[0].note_card.note_id` / `cards[0].id` | `6a366131000000002101aa61` |
| title | `cards[0].note_card.title` | `三亚3天2晚旅游攻略🌴｜节奏松弛不赶路！` |
| note_desc | `cards[0].note_card.desc` | 正文全文 |
| note_type | `cards[0].note_card.type` | `normal` |
| cover_url | `cards[0].note_card.image_list[0].url_default` | 首图 default URL |
| image_list | `cards[0].note_card.image_list[]` 提取 url_default | JSON 数组 |
| tag_list | `cards[0].note_card.tag_list[]` | `[{"name":"三亚旅游攻略","id":"...","type":"topic"}]` |
| ip_location | `cards[0].note_card.ip_location` | `江苏` |
| author_id | `cards[0].note_card.user.user_id` | `5e15586000000000010012c9` |
| author_name | `cards[0].note_card.user.nick_name` | `小小小提米。` |
| author_avatar | `cards[0].note_card.user.avatar` | avatar URL |
| total_likes | `cards[0].note_card.interact_info.liked_count` | `84` |
| total_collect | `cards[0].note_card.interact_info.collected_count` | `52` |
| total_comments | `cards[0].note_card.interact_info.comment_count` | `21` |
| total_shares | `cards[0].note_card.interact_info.share_count` | `1` |
| publish_time | `cards[0].note_card.time`（毫秒时间戳→datetime） | `1781948721000` |
| last_update_time | `cards[0].note_card.last_update_time`（毫秒→datetime） | `1781948722000` |
| xsec_token | `cards[0].xsec_token` / `cards[0].note_card.xsec_token` | `ABP7J72C...` |
| at_user_list | `cards[0].note_card.at_user_list` | `[]` |
| keyword | 从 subTaskParams 提取 | 搜索关键词 |
| ip_location | `cards[0].note_card.ip_location` | `江苏` |

> **🏷️ label 字段：**
> 结构参考 `material_base.material_label`：`{"common_tag":[],"poi":[],"city":[],"ai_tag":[]}`
> 由 `RedbookNotePostProcessStrategy` 在入库时从 keyword（搜索词）+ title/desc 中的 `#tag` 合并到 `common_tag`（去重），poi/city/ai_tag 暂不填充。

> **⚠️ DTO 缺失字段：** `XhsCrawlDetailTaskResultData.NoteCard` 当前没有 `ip_location` 和 `at_user_list` 字段，
> 需要在 DTO 中补充：
> ```java
> // XhsCrawlDetailTaskResultData.NoteCard 新增
> private String ipLocation;
> private List<AtUserItem> atUserList;
>
> @Data
> public static class AtUserItem {
>     private String userId;
>     private String nickName;
> }
> ```

> **📊 首日数据（存于 extra JSON）：**
>
> preCrawl（bigSearch）回调阶段从 `note_card.interact_info` 提取，存于 `redbook_note_post.extra` 字段：
> | extra 字段 | BigSearch 报文路径 | 说明 |
> |-----------|-------------------|------|
> | `firstDayLikes` | `items[].note_card.interact_info.liked_count` | 首日点赞数 |
> | `firstDayCollects` | `items[].note_card.interact_info.collected_count` | 首日收藏数 |
> | `firstDayComments` | `items[].note_card.interact_info.comment_count` | 首日评论数 |
>
> 仅在 preCrawl 链路写入，postCrawl detail 回调不覆盖。定时任务只刷新表字段 `total_likes/collect/comments/shares`，不影响 extra 中首日数据。

---

## 3. UserInfo 回调 → `redbook_author_info` 字段映射

| 表字段                 | 报文路径                                      | 示例值                                         |
| ------------------- | ----------------------------------------- | ------------------------------------------- |
| author_id           | `data.data.data.userid`                   | `61a39f950000000010005f17`                  |
| nickname            | `data.data.data.nickname`                 | `KK教穿搭`                                     |
| avatar_url          | `data.data.data.images`                   | avatar URL                                  |
| description         | `data.data.data.desc`                     | `分享日常穿搭`                                    |
| gender              | `data.data.data.gender`                   | `0`（0-未知 1-男 2-女）                           |
| follower_count      | `data.data.data.fans`                     | `8624`                                      |
| following_count     | `data.data.data.follows`                  | `2`                                         |
| note_count          | `data.data.data.note_num_stat.posted`     | `160`                                       |
| total_liked         | `data.data.data.liked`                    | `24300`                                     |
| total_collected     | `data.data.data.collected`                | `13339`                                     |
| location            | `data.data.data.location`                 | `中国  浙江  杭州`                                |
| ip_location         | `data.data.data.ip_location`              | `安徽`                                        |
| red_id              | `data.data.data.red_id`                   | `8062790348`                                |
| red_official_verify | `data.data.data.red_official_verify_type` | `0`（0-未认证）                                  |
| tags                | `data.data.data.tags[]`                   | `[{"name":"时尚博主","tag_type":"profession"}]` |
| is_seller           | `data.data.data.seller_info != null`      | `1`（有店铺）                                    |
| is_buyer            | `data.data.data.buyer_info != null`       | `1`（有橱窗）                                    |
| share_link          | `data.data.data.share_link`               | `https://www.xiaohongshu.com/user/profile/...` |


---

## 4. author 子任务请求参数（下发给爬取引擎）

```json
{
    "source": "redbook",
    "taskType": "userInfo",
    "businessType": "mkt_odin",
    "priority": 3,
    "expireAt": "2035-01-01 00:00:00",
    "taskId": "<crawlTaskIdCodec.encode(subTaskId)>",
    "param": {
        "userId": "<author_user_id>"
    }
}
```

> subTaskParams（存储于 SubTask 表，给 CrawlTaskResultProcessor 路由用）需多一个 `crawlType` 字段：
> ```json
> { "source":"redbook", "businessType":"mkt_odin", "taskType":"userInfo",
>   "crawlType":"userInfo",  ← 必须，否则 context 构建失败
>   "userId":"...", "keyword":"...", "priority":3, "expireAt":"2035-01-01 00:00:00" }
> ```

## 5. detail 子任务请求参数（下发给爬取引擎）

```json
{
    "source": "redbook",
    "taskType": "detail",
    "businessType": "mkt_odin",
    "priority": 3,
    "expireAt": "2035-01-01 00:00:00",
    "taskId": "<crawlTaskIdCodec.encode(subTaskId)>",
    "param": {
        "noteId": "<note_id>",
        "xsecToken": "<xsec_token>"
    }
}
```

> subTaskParams（存储于 SubTask 表）需多一个 `crawlType` 字段：
> ```json
> { "source":"redbook", "businessType":"mkt_odin", "taskType":"detail",
>   "crawlType":"detail",  ← 必须
>   "noteId":"...", "xsecToken":"...", "keyword":"...", "priority":3, "expireAt":"..." }
> ```

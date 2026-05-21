# content_image / content_video 唯一键改造方案

## Context

当前 `content_image` UNIQUE KEY 在 `original_url`，`content_video` UNIQUE KEY 在 `video_url`。URL 可能超过 2048 字节，MySQL InnoDB 限制前缀索引最大 767 字节，导致建表时 `Specified key 'uniq_video_url' was too long; max key length is 767 bytes`。

**各环境情况：**
- **Prod**：尚未建表，DDL 直接包含 `url_hash` + `uniq_url_hash`，无迁移成本
- **Beta**：已有数据和旧索引，需要迁移

## 方案

新增 `url_hash` 列（VARCHAR(64)），存储 URL 的 MD5 hex（固定 32 字节），unique key 建在 `url_hash` 上。

MD5 输出固定 128 bit = 16 字节 = 32 hex 字符，远低于 767 字节限制。碰撞概率 1/2^128，URL 去重场景足够安全。

## Beta 迁移步骤

按顺序执行，逐表操作：

```sql
-- Step 1: 加列（无唯一约束，瞬间完成）
ALTER TABLE content_image ADD COLUMN `url_hash` VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'URL的MD5，UNIQUE去重键' AFTER `original_url`;
ALTER TABLE content_video ADD COLUMN `url_hash` VARCHAR(64) NOT NULL DEFAULT '' COMMENT 'URL的MD5，UNIQUE去重键' AFTER `video_url`;

-- Step 2: 回填历史数据（MySQL 内置 MD5 函数）
UPDATE content_image SET url_hash = MD5(original_url) WHERE url_hash = '';
UPDATE content_video SET url_hash = MD5(video_url) WHERE url_hash = '';

-- Step 3: 检查碰撞
SELECT url_hash, COUNT(*) FROM content_image GROUP BY url_hash HAVING COUNT(*) > 1;
SELECT url_hash, COUNT(*) FROM content_video GROUP BY url_hash HAVING COUNT(*) > 1;

-- Step 4: 删旧索引，建新唯一索引（无碰撞时）
ALTER TABLE content_image DROP KEY `uniq_original_url`, ADD UNIQUE KEY `uniq_url_hash` (`url_hash`);
ALTER TABLE content_video DROP KEY `uniq_video_url`, ADD UNIQUE KEY `uniq_url_hash` (`url_hash`);
```

## Prod DDL

直接包含 url_hash + 唯一索引，无迁移成本。

## 改动清单

### 1. Entity 改动

**ContentImage.java** — 新增字段
```java
/** original_url 的 MD5，唯一键 */
private String urlHash;
```

**ContentVideo.java** — 新增字段
```java
/** video_url 的 MD5，唯一键 */
private String urlHash;
```

### 2. Mapper XML 改动

**ContentImageMapper.xml**
- `Base_Column_List` 新增 `url_hash`
- `BaseResultMap` 新增 `url_hash` 列映射
- `insert` SQL 包含 `url_hash` 列
- 新增 `selectByUrlHash` 查询

```xml
<select id="selectByUrlHash" resultMap="BaseResultMap">
    SELECT <include refid="Base_Column_List"/>
    FROM content_image
    WHERE url_hash = #{urlHash}
    LIMIT 1
</select>
```

**ContentVideoMapper.xml** — 同理。

### 3. Mapper Java 接口改动

**ContentImageMapper.java**
```java
ContentImage selectByUrlHash(@Param("urlHash") String urlHash);
```

**ContentVideoMapper.java**
```java
ContentVideo selectByUrlHash(@Param("urlHash") String urlHash);
```

### 4. MD5 工具方法

**新增 `infra/util/HashUtils.java`：**

```java
package com.qunar.ug.flight.contact.odin.server.infra.util;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;

public class HashUtils {

    private static final char[] HEX_DIGITS = "0123456789abcdef".toCharArray();

    public static String md5(String input) {
        if (input == null) return "";
        try {
            MessageDigest md = MessageDigest.getInstance("MD5");
            byte[] bytes = md.digest(input.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(32);
            for (byte b : bytes) {
                sb.append(HEX_DIGITS[(b >> 4) & 0xf]);
                sb.append(HEX_DIGITS[b & 0xf]);
            }
            return sb.toString();
        } catch (NoSuchAlgorithmException e) {
            throw new RuntimeException("MD5 not available", e);
        }
    }
}
```

### 5. 业务逻辑改动

**RawContentSyncServiceImpl.java**

三处 insert/去查前使用 `urlHash`：

`buildImages()`：
```java
// 查询去重改为 url_hash
ContentImage existing = contentImageMapper.selectByUrlHash(HashUtils.md5(url));
if (existing != null) {
    imageIds.add(existing.getId());
    continue;
}

// insert 前设置 url_hash
ContentImage image = new ContentImage();
image.setUrlHash(HashUtils.md5(url));
// ... 其余字段不变
contentImageMapper.insert(image);
```

`buildVideo()`：
```java
ContentVideo existing = contentVideoMapper.selectByUrlHash(HashUtils.md5(raw.getContentUrl()));
if (existing != null) {
    return Collections.singletonList(existing.getId());
}

ContentVideo video = new ContentVideo();
video.setUrlHash(HashUtils.md5(raw.getContentUrl()));
// ... 其余字段不变
contentVideoMapper.insert(video);
```

`buildVideoCover()`：
```java
ContentImage existing = contentImageMapper.selectByUrlHash(HashUtils.md5(raw.getVideoCoverUrl()));
if (existing != null) {
    return Collections.singletonList(existing.getId());
}

ContentImage cover = new ContentImage();
cover.setUrlHash(HashUtils.md5(raw.getVideoCoverUrl()));
// ... 其余字段不变
contentImageMapper.insert(cover);
```

### 6. Mapper XML 中 insert SQL

**ContentImageMapper.xml：**
```sql
INSERT INTO content_image (
    image_type, original_url, url_hash, internal_url, width, height, aspect_ratio,
    image_size, content_title, poi, ext_param
) VALUES (
    #{imageType}, #{originalUrl}, #{urlHash}, #{internalUrl}, #{width}, #{height}, #{aspectRatio},
    #{imageSize}, #{contentTitle}, #{poi}, #{extParam}
)
```

**ContentVideoMapper.xml：** 同理。

## 影响范围

| 文件 | 改动 |
|------|------|
| `ContentImage.java` | 新增 `urlHash` 字段 |
| `ContentVideo.java` | 新增 `urlHash` 字段 |
| `ContentImageMapper.java` | 新增 `selectByUrlHash` 方法 |
| `ContentVideoMapper.java` | 新增 `selectByUrlHash` 方法 |
| `ContentImageMapper.xml` | 列清单 + insert + 新查询 |
| `ContentVideoMapper.xml` | 列清单 + insert + 新查询 |
| `HashUtils.java` | **新建** MD5 工具类 |
| `RawContentSyncServiceImpl.java` | 3 处 insert/去查使用 urlHash |
| Beta DDL | 4 条 ALTER + 2 条 UPDATE 回填 |
| Prod DDL | DDL 中直接包含 url_hash + unique key |

## 验证

1. `HashUtils.md5("hello")` = `"5d41402abc4b2a76b9719d911017c592"`
2. Beta 本地跑同步，观察去重逻辑正常
3. 确认 767 字节错误不再出现
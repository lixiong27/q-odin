-- ============================================================
-- RawContentSyncTask 业务表 — 完整建表 DDL
-- 版本: v2 (去掉 base_id，关系集中到 content_base.content_relations)
-- ============================================================

-- -----------------------------------------------------------
-- 1. content_base（内容基础信息表）
-- -----------------------------------------------------------
CREATE TABLE `content_base` (
    `id`                  BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `content_id`          VARCHAR(64) NOT NULL DEFAULT '' COMMENT '内容ID，外部唯一标识',
    `business_content_id` VARCHAR(64) NOT NULL DEFAULT '' COMMENT '业务内容ID',
    `content_type`        VARCHAR(32) NOT NULL DEFAULT '' COMMENT '内容形式：图文帖、短视频',
    `content_title`       VARCHAR(500) NOT NULL DEFAULT '' COMMENT '内容标题',
    `publish_platform`    VARCHAR(32) NOT NULL DEFAULT '' COMMENT '发布平台：小红书、抖音',
    `publish_time`        DATETIME NOT NULL DEFAULT '1970-01-01 00:00:00' COMMENT '发布时间',
    `publish_url`         VARCHAR(1024) NOT NULL DEFAULT '' COMMENT '发布链接',
    `business_line`       VARCHAR(64) NOT NULL DEFAULT '' COMMENT '业务线：hotel、public',
    `content_source`      VARCHAR(64) NOT NULL DEFAULT '' COMMENT '内容来源/大业务方向划分',
    `production_team`     VARCHAR(128) NOT NULL DEFAULT '' COMMENT '生产归属团队/投放团队/代理名称',
    `operation_project`   VARCHAR(128) NOT NULL DEFAULT '' COMMENT '运营项目',
    `placement_position`  VARCHAR(128) NOT NULL DEFAULT '' COMMENT '投放版位',
    `dt`                  DATE NOT NULL DEFAULT '1970-01-01' COMMENT '数据更新日期，标识最新版本',

    -- 关联关系（统一维护 text/image/video 的子表 ID 引用）
    `content_relations`   JSON NOT NULL COMMENT '关联关系，如 {"text_ids":[1],"image_ids":[1,2],"video_ids":[3]}',

    `create_time`         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_content_id` (`content_id`),
    KEY `idx_business_content_id` (`business_content_id`),
    KEY `idx_publish_platform` (`publish_platform`),
    KEY `idx_publish_time` (`publish_time`),
    KEY `idx_business_line` (`business_line`),
    KEY `idx_content_type` (`content_type`),
    KEY `idx_biz_ctime` (`business_line`, `publish_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内容基础信息表';

-- -----------------------------------------------------------
-- 2. content_text（内容文本表）
-- -----------------------------------------------------------
CREATE TABLE `content_text` (
    `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `content_title`     VARCHAR(500) NOT NULL DEFAULT '' COMMENT '内容标题（冗余）',
    `content_text`      LONGTEXT COMMENT '内容文案/正文',
    `poi`               VARCHAR(1000) NOT NULL DEFAULT '' COMMENT 'POI（冗余）',
    `text_length`       INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '正文字数',
    `ext_param`         VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    `create_time`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内容文本表';

-- -----------------------------------------------------------
-- 3. content_image（内容图片表）
-- -----------------------------------------------------------
CREATE TABLE `content_image` (
    `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `image_type`        VARCHAR(32) NOT NULL DEFAULT '' COMMENT '图片类型，如正文图/封面图',
    `original_url`      VARCHAR(520) NOT NULL DEFAULT '' COMMENT '原始图片链接',
    `internal_url`      VARCHAR(520) NOT NULL DEFAULT '' COMMENT '转存内部OSS链接',
    `width`             INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '图片宽度(px)',
    `height`            INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '图片高度(px)',
    `aspect_ratio`      DECIMAL(8,4) NOT NULL DEFAULT 0.0000 COMMENT '宽高比(width/height)',
    `image_size`        INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '图片大小(字节)',
    `content_title`     VARCHAR(500) NOT NULL DEFAULT '' COMMENT '内容标题（冗余）',
    `poi`               VARCHAR(1000) NOT NULL DEFAULT '' COMMENT 'POI（冗余）',
    `ext_param`         VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    `create_time`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_original_url` (`original_url`(255))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内容图片表';

-- -----------------------------------------------------------
-- 4. content_video（内容视频表）
-- -----------------------------------------------------------
CREATE TABLE `content_video` (
    `id`                    BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `video_url`             VARCHAR(520) NOT NULL DEFAULT '' COMMENT '原始视频链接',
    `internal_video_url`    VARCHAR(520) NOT NULL DEFAULT '' COMMENT '转存内部OSS视频链接',
    `video_cover_url`       VARCHAR(520) NOT NULL DEFAULT '' COMMENT '视频封面图链接',
    `duration`              INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频时长(秒)',
    `width`                 INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频宽度(px)',
    `height`                INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频高度(px)',
    `aspect_ratio`          DECIMAL(8,4) NOT NULL DEFAULT 0.0000 COMMENT '宽高比(width/height)',
    `video_size`            INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '视频文件大小(字节)',
    `video_format`          VARCHAR(16) NOT NULL DEFAULT '' COMMENT '视频格式(mp4/mov等)',
    `video_frame_param`     VARCHAR(6000) NOT NULL DEFAULT '{"frame":[]}' COMMENT '抽帧参数JSON',
    `audio_url`             VARCHAR(520) NOT NULL DEFAULT '' COMMENT '提取的音频文件链接',
    `audio_text`            TEXT COMMENT '音频转文字内容',
    `preprocess_status`     TINYINT NOT NULL DEFAULT 0 COMMENT '预处理状态：0-未处理，1-已抽帧，2-已提取音频，3-已转文字，4-全部完成',
    `content_title`         VARCHAR(500) NOT NULL DEFAULT '' COMMENT '内容标题（冗余）',
    `poi`                   VARCHAR(1000) NOT NULL DEFAULT '' COMMENT 'POI（冗余）',
    `ext_param`             VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    `create_time`           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_video_url` (`video_url`(255)),
    KEY `idx_preprocess_status` (`preprocess_status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内容视频表';

-- -----------------------------------------------------------
-- 5. content_metrics（内容指标表）
-- -----------------------------------------------------------
CREATE TABLE `content_metrics` (
    `id`                          BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `base_id`                     BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '关联 content_base.id',

    -- 曝光与点击指标
    `total_impressions`           INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计曝光量',
    `total_clicks`                INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计点击量',
    `total_reads`                 INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计阅读量',
    `total_interactions`          INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计互动数',

    -- 完播与跳出率
    `completion_rate`             DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '完播率(%)',
    `three_sec_completion_rate`   DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '3s完播率(%)',
    `five_sec_completion_rate`    DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '5s完播率(%)',
    `two_sec_bounce_rate`         DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '2s跳出率(%)',

    -- 成本与转化指标
    `cpm`                         DECIMAL(8,4) NOT NULL DEFAULT 0.0000 COMMENT '千次曝光成本(CPM)',
    `ctr`                         DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '点击率(CTR)(%)',
    `cvr`                         DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '转化率(CVR)(%)',

    -- App与用户增长指标
    `app_downloads`               INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'App下载量',
    `new_activations`             INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '新激活UV',
    `new_registrations`           INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '新注册UV',

    -- 引流与归因指标
    `drive_uv`                    INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '引流UV',
    `exposure_to_read_ratio`      DECIMAL(8,3) NOT NULL DEFAULT 0.000 COMMENT '曝光/阅读引流比',
    `potential_new_uv`            INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '潜新UV',
    `potential_new_cac`           DECIMAL(9,3) NOT NULL DEFAULT 0.00 COMMENT '潜新CAC',
    `attributed_new_customers`    INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '归一新客量',
    `new_customer_cac`            DECIMAL(9,3) NOT NULL DEFAULT 0.00 COMMENT '新客CAC',

    -- 订单指标
    `order_uv`                    INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计下单UV',
    `total_orders`                INT UNSIGNED NOT NULL DEFAULT 0 COMMENT '累计订单量',

    -- 扩展与审计
    `ext_param`                   VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    `create_time`                 DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`                 DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',

    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_base_id` (`base_id`),
    KEY `idx_total_impressions` (`total_impressions`),
    KEY `idx_total_orders` (`total_orders`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内容指标表';

-- -----------------------------------------------------------
-- 6. content_label（内容标签表）
-- -----------------------------------------------------------
CREATE TABLE `content_label` (
    `id`                BIGINT UNSIGNED NOT NULL AUTO_INCREMENT COMMENT '自增主键',
    `base_id`           BIGINT UNSIGNED NOT NULL DEFAULT 0 COMMENT '关联 content_base.id',
    `city`              VARCHAR(500) NOT NULL DEFAULT '' COMMENT '城市，多个用逗号分隔',
    `poi`               VARCHAR(1000) NOT NULL DEFAULT '' COMMENT 'POI，多个用逗号分隔',
    `ai_tag`            JSON NOT NULL COMMENT 'AI标签列表，用于ES检索',
    `ai_tag_detail`     MEDIUMTEXT COMMENT 'AI全量分析结果JSON',
    `task_id`           VARCHAR(64) NOT NULL DEFAULT '' COMMENT '关联AI任务ID',
    `ext_param`         VARCHAR(3000) NOT NULL DEFAULT '{}' COMMENT '扩展参数JSON',
    `create_time`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT '创建时间',
    `update_time`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP COMMENT '更新时间',
    PRIMARY KEY (`id`),
    UNIQUE KEY `uniq_base_id` (`base_id`),
    KEY `idx_task_id` (`task_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='内容标签表';
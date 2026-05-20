# 获取userId代码参考
D:\Users\qixiong.li\IdeaProjects\ares_live\src\main\java\com\qunar\marketing\ares\live\infrastructure\utils\UserIdUtil.java

参考前后端工程代码
后端
D:\Users\qixiong.li\IdeaProjects\ares_live
前端
D:\Users\qixiong.li\IdeaProjects\ares_node


# 认证登录接入

## 1、后端代码接入动作

后端直接引入jar包即可，无需更改其他代码，我们在jar包里提供了QSSO后端登录接口。

需要注意的是，后端实现认证和鉴权使用的是Filter做拦截，如果项目代码里有其他的Filter，测试的时候可以看下Filter的先后顺序是否存在问题。

## 2、前端代码接入动作

### **a、前后端分离项目**

- 如果是前后端端分离项目，前端接入分成三部分，
    
    - 校验登录状态
        
    - 跳转Url登录界面
        
    - 退出QSSO登录
        

#### **① 校验登录状态**

 前端校验登录状态有两种方式：

1. 前端访问任意后端接口时，如果后端校验出用户未QSSO登录，会返回HTTP状态码为401的异常响应结果，这种方式需要前端配置一个全局的响应拦截器，来检测未登录的HTTP 401 状态码，如果检测到了再跳转到QSSO登录页面。
    

```Java
{
        "message":"用户未登录"
}
```

2. 后端还提供了一个统一的当前是否用户登录的校验接口，前端可以在适当位置调用校验接口判断登录状态，如果未登录则跳转QSSO登录接口。
    

**接口URL** ：GET：/_/upms/qsso/isLogin

**响应结果：**

```Java
// 已登录
{
        "status":0,
        "message":"已登录",
        "data":true
}
// 未登录
{
        "status":0,
        "message":"未登录",
        "data":false
}
// 内部异常
{
        "status":-1,
        "message":"判断用户是否登录内部异常",
        "data":null
}
```

#### **② 跳转****QSSO****登录页面**

跳转QSSO登录页面我们也提供了两种方式，前端开发同学可自行判断哪个更方便来选用不同的方式

1. 前端同学自己添加下面的HTML页面，在按照第一步检查到QSSO未登录时，跳转到该页面，让用户点击登录，注意如果需要登录成功后重定向到当前页面地址，则要把当前页面地址转码后以‘upmsRedirect’作为参数名附加在登陆地址后面
    

```XML
<html>

<!-- 添加一个登录按钮 -->
<button id="qsso-login">qsso登录</button>

<!-- 引入qsso auth js库 -->
<script src="https://qsso.corp.qunar.com/lib/qsso-auth.js"></script>

<script>

// 调用QSSO.attach进行登录参数的设置，第一个参数为绑定登录事件的HTML元素，第二个参数为登录成功后接收token的后端登录接口URI。
// 本jar包的后端登录地址为：'/_/upms/qsso/login'
// 如果需要登录成功后重定向到当前页面地址，则要把当前页面地址转码后以‘upmsRedirect’作为参数名附加在登陆地址后面，例如：'/_/upms/qsso/login?upmsRedirect=' + encodeURIComponent(location.href)

QSSO.attach('qsso-login','/_/upms/qsso/login?upmsRedirect=' + encodeURIComponent(location.href));

// attach函数会将HTMLid为qsso-login的元素onclick时自动去qsso登录，当用户用户点击上面的button，会跳到qsso登录页面, 用户在qsso登录后会自动携带token去调用attach中的第二个登录地址，即“/_/upms/qsso/login”
// 这里如果不想让用户点击登录按钮跳转，可以直接使用document.querySelector("#qsso-login").click()自动跳转

</script>
<!-- 结束 -->

<html>
```

2. （推荐） 我们后端也提供了一个获取上述HTML页面的接口，前端同学也可以直接调用我们的接口，来跳转到QSSO登录页面， **注意这里不能直接使用ajax去请求，需要用访问页面的方式**
    

 **接口URL** ：GET：/_/upms/qsso/loginHtml

**请求参数：** upmsRedirect：用户登录成功后要返回的地址，注意要先转码后再传参

**响应结果：** 会将请求参数upmsRedirect 拼接到上述HTML页面中返回

#### **③ 退出****QSSO****登录**

我们后端jar包中同样提供了一个退出QSSO登录的接口，调用这个接口会移除QSSO登录的状态，并返会登录按钮界面，即和访问loginHtml返回的一样

 **接口URL** ：GET：/_/upms/qsso/logout

**请求参数：** upmsRedirect：用户登录成功后要返回的地址，注意要先转码后再传参，用户退出登录后，如果再点击登录按钮，登录后会跳转到这个地址，建议设置为项目首页地址。

**响应结果：** 会将请求参数upmsRedirect 拼接到上述登录按钮HTML页面中返回

## 3、使用自定义用户认证逻辑

如果系统仅期望接入UPMS系统鉴权，且目前已存在符合安全规范的用户认证方法，不想使用本jar包下的QSSO认证，

则需要自定义从HttpServletRequest中获取UserInfo的方法，即自己实现jar包中的 UserInfoProvider 接口，并将实现类的全限定名，配置在qunar-tc-auth.properties文件中的qsso.custom.userInfoProvider属性中

**自定义用户信息获取接口**

> 展开源码

```Java
public interface UserInfoProvider {
 
    /**
     * 获取用户信息
     * @return 用户信息，如果 userInfo == null 则标识当前用户未登录
     */
    UserInfo obtainUserInfo(HttpServletRequest request);
}

public class UserInfo {
    private final String qtalkId; 
}
```



# 权限校验接入方法

注意：客户端端内部有个一分钟过期的缓存，因此在upms平台配置好资源后，通过客户端内部来获取前端和后端资源会有一分钟的延迟。

## 1、在UPMS平台配置项目

使用本jar包前，请确保已经在UPMS平台已创建好项目、资源、角色、用户等资源管理项。UPMS系统的业务流程如下：

目前UPMS存在一个老的系统： [http://upms.corp.qunar.com/page/myprojects](http://upms.corp.qunar.com/page/myprojects) ，目前要接入的话，请确保已在老的UPMS系统上创建好了上述提到的几项。

![](https://hf7l9aiqzx.feishu.cn/space/api/box/stream/download/asynccode/?code=NGFhMjg3YjBiZjVmZDc5ODM4MGI1ZWQxY2Y2MThjMjZfYkFXeVA5NHdWQ3F4SjBCaW5sOVQyampSaWdDZ3g1U2RfVG9rZW46QWQ5R2JVTHN4b2hvcEN4TG5QR2NZTUN4bnVlXzE3NzkyNTUzNTI6MTc3OTI1ODk1Ml9WNA)

老upms系统的使用说明如下：

- upms系统链接：
    
    - prod: [http://upms.corp.qunar.com/](http://upms.corp.qunar.com/)
        
    - beta: [http://upms.beta.qunar.com](http://upms.beta.qunar.com/)
        
- 若要登录upms系统，需要联系upms负责人添加用户并分配upms系统的《普通用户》角色
    
- 若要在upms中创建项目、添加资源、角色、用户及创建关联关系等操作，需联系upms负责人添加upms系统的《系统管理员》角色
    

在7月10号左右，我们会升级一个新的资源管理平台系统，会比老系统更加人性化好用，以及更加符合安全规范

如果大家时间比较急，可以先使用老UPMS系统来做资源管理，后续新平台搭建好后，会将资源无缝切换到新UPMS系统

## 2、后端接口权限校验

### a、配置拦截路径

在qunar-tc-auth.properties文件中的upms.authz.url属性中配置需要鉴权的路径，多个以英文逗号分隔，支持AntPathMatcher风格匹配

### b、拦截时的响应

请求鉴权被拦截时，会返回 HTTP 403 状态码，同时responseBody会说明具体的拦截原因，前端可将原因展示给用户，引导用户去upms平台上申请资源

主要的原因有以下几点：

```Java
{
        "message":"鉴权失败，用户还没注册upms"
}
{
        "message":"鉴权失败，未找到用户在当前项目的角色, 请前往upms平台申请"
}
{
        "message":"鉴权失败，用户没有权限访问该资源, 请前往upms平台申请对应角色"
}
```

### c、未拦截时获取拦截的状态

**（1.0.2版本支持）**

当请求通过我们的权限校验时，可能存在以下几种情况

1. 请求未走我们的认证和鉴权流程
    
2. 请求路径未在配置文件中配置鉴权，仅走了用户认证逻辑
    
3. 请求路径在配置文件中配置为ignore路径
    
4. 鉴权在配置文件中被禁用
    
5. 鉴权通过
    
6. 鉴权未通过，但是开启了dryRun开关
    
7. 鉴权未通过，但是用户在白名单中
    

如果在系统内部想区分这三种情况分别做逻辑处理，可以通过我们提供的工具类UpmsStatusUtils来区分：

```Java
public class UpmsStatusObtainUtil {

    /**
     * 获取鉴权状态
     * @return 鉴权状态
     */
    public static UpmsStatus obtainStatus();
}

public class UpmsStatus {
    private String key;
    private String desc;
}
```

UpmsStatus有以下几种取值：

注意：获取UpmsStatus不能跨线程，跨线程获取到的值为null

## 3、前端资源权限校验

### a、前后端分离项目

会在jar包中提供一个根据用户来获取当前用户所拥有资源的接口，前端根据接口获取到的资源，自行进行权限校验

 **接口URL** ：GET：/_/upms/authz/query/user/resources

**请求参数：无**

**响应结果：**

```Java
// 用户未登录
{
        "status":-1,
        "message":"用户未登录",
        "data":null
}
// 内部异常
{
        "status":-1,
        "message":"查询用户前端资源失败",
        "data":null
}
// 查询成功
{
  "status": 0,
  "message": "查询用户前端资源成功",
  "data": {
    "projectId": "projectX",
    "qtalkId": "user123",
    "resources": [
      {
        "id": 1,
        "name": "菜单A",
        "path": "/parent",
        "type": "MENU",
        "projectId": 1,
        "appCode": "",
        "treeOrder": 0,
        "children": [
          {
            "id": 2,
            "name": "",
            "path": "/child1",
            "type": "MENU",
            "projectId": 1,
            "appCode": "",
            "treeOrder": 1,
            "children": [
              
            ]
          },
          {
            "id": 3,
            "name": "ChildResource2",
            "path": "/child2",
            "type": "INTERFACE",
            "projectId": 1,
            "appCode": "app2",
            "treeOrder": 2,
            "children": [
             
            ]
          }
        ]
      }
    ]
  }
}
```

### b、前后端不分离项目

在项目代码中使用client中 [com.qunar.tc](http://com.qunar.tc).upms.auth.api.service.ResourceObtainUtil#getFeUserResource方法获取，获取到结果和上面的响应结果一致。

## 4、用户申请角色

当用户想访问某个资源，但是被拦截后，说明用户没有该系统对应资源的角色，这是可前往upms系统申请

目前老upms支持在upms-plus系统上进行申请： [http://upmsplus.corp.qunar.com/rock/page/7702](http://upmsplus.corp.qunar.com/rock/page/7702)

后续等待新平台开发完成后，会支持直接在新upms平台进行申请，更加人性化，更加符合安全规范

# 七、安全审计日志接入方法
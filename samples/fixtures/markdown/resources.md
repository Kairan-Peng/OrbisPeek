# 图片与脚本边界

同目录子文件应显示：
![允许的本地图片](assets/local-swatch.png)

带空格路径应可解码：
![空格路径](assets/local%20swatch.png)

以下资源应被阻止，不能因为宿主预览成功就认为沙盒扩展也成功：
![远程资源](https://example.invalid/remote.png)
![父目录资源](../outside.png)
![符号链接越界](assets/outside-link.png)
![绝对文件路径](file:///etc/passwd)
![本地SVG](assets/unsafe.svg)

<script>window.quicklookFixtureScriptExecuted = true; document.title = "UNSAFE_SCRIPT_EXECUTED";</script>
<img src="https://example.invalid/html-image.png" onerror="window.quicklookFixtureScriptExecuted=true">

原始 HTML 应显示为文本或被安全处理，不应执行。

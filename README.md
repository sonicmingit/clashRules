# clashRules
自用

## subCoverter

配合[项目](https://github.com/sonicmingit/sub-web)
piblic->config.yaml使用

docker镜像：
**sonicming/sub-web-config**

```yaml
version: '3.3'
services:
  # 后端
  subconverter:
    container_name: subconverter
    # volumes:
    #   - /mnt/data_sdb1/home/docker/subconverter/configs:/base      
    ports:
      - '58081:25500'
    restart: always
    image: tindy2013/subconverter
  # 前端
  subweb:
    container_name: subweb
    ports:
      - '58080:80'
    restart: always
    image: sonicming/sub-web-config:1.0
    volumes:
      - /home/docker/subweb/conf/config.yaml:/usr/share/nginx/html/config.yaml
```

`config.yaml`对应 `subCoverter/config.yaml`文件


## subConfig
转换配置文件，用于subCoverter中的配置
📌自定义规则修改


## rules
单独规则，配合subConfig使用
📌自定义规则匹配修改





# fallback
https://raw.githubusercontent.com/wxfyes/cf/main/openclashfallback.txt

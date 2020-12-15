# 基于 Github Actions 和 Docker Hub 的项目开发部署流程

本文主要从开发者的视角，介绍一种基于 Docker 容器和 Github Actions 的开发，测试和部署流程。

大致来说，主要有以下关键步骤：
- 使用 Docker 将项目容器化；
- 使用 Github Actions 监听 Github 仓库特定事件的触发(这里是 `push` 事件)，然后执行相应的自动化操作；
- 这里的自动化操作包括：运行项目的测试用例；如果测试用例全部通过，则构建生产版本镜像到 Docker Hub 对应的项目仓库;
- Docker Hub 仓库设置 Webhook 钩子，订阅新镜像推送事件，来触发自动部署；

项目代码可以在 [github](https://github.com/hyf152632/docker_with_github_actions_demo)找到。

## 1. 项目容器化

Docker 是个好东西。它为开发者提供了一个使用容器构建，运行和分享应用程序的平台。它降低了 Linux 容器的使用门槛，使普通开发者也可以轻易的实现应用程序(及其环境)的相互隔离。  
这让你的开发环境不会再轻而易举就变得凌乱。而且你也可以轻松的构建打包自己的应用程序及其环境。
然后方便的将其部署到其他任何安装了 Docker 的开发环境中。

可以很方便的将项目 Docker 化。首先需要在开发环境[安装 Docker](https://docs.docker.com/desktop/)。然后，在项目根目录添加一个名为 `Dockerfile` 的文本文件。  
比如下面👇这样：

``` Dockerfile
FROM node:14.15.1 as builder

WORKDIR /usr/app

COPY package.json /usr/app/

RUN npm install --silent --no-cache --registry=https://registry.npm.taobao.org

COPY  ./ ./

RUN npm run build && mv /usr/app/build/* /usr/src && rm -rf /usr/app

FROM nginx:latest

COPY --from=builder /usr/src /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
```

关于 `Dockerfile` 文件的语法详情请参考[Docker 官网](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/)。
有了 `Dockerfile` 文件之后，我们通过在命令行键入 `docker build -t <镜像命> .` 命令来生成一个 Docker 镜像。
Docker 镜像提供了运行你打包的程序的任何东西，比如：代码或者二进制码，运行时，项目依赖和你应用程序需要的文件系统。
然后，你可以通过`docker run <容器名称> <镜像名称>`来生成并运行一个 Docker 镜像的 Docker 容器。 Docker 容器可以认为是 Docker 镜像 的 "实例"。
你可以通过 Docker 镜像 “实例化” 多个 Docker 容器，然后愉快的将其跑起来。 但是涉及到实际项目的时候，可能我们一个项目需要同时跑多个 Docker 容器。  
这个时候仅仅通过定义 `Dockerfile` 的这种方法就显得有些吃力。所以 Docker 又提供了 `docker-compose` 来应对这种多 Docker 容器相关联的场景。  
你可以在项目的根目录下定义一个 `docker-compose.yml` 文件。
比如下面👇这样的：

``` yml
version: '3.9'

services:
  web_prod:
    build: .
    ports:
      - '80:80'
    container_name: 'web_prod'
```

在 `docker-compose.yml` 中配置你项目用到的容器，然后通过一键执行 `docker-compose up` 来生成项目中定义的多个镜像并使之运行。
关于 `docker-compose.yml` 文件的语法详情请参考[Docker 官网](https://docs.docker.com/compose/)
现在你的应用程序就成功跑在与系统环境相对隔离的 Docker 容器里了。其实运行在容器中是一把双刃剑，一方面容器的隔离效果为应用自身和开发环境带来了更安全更解耦的好处，
另一方面，隔离效果也带来了容器之间，和容器与环境之间相互访问的不便之处。当然这种不便主要体现在你刚上手 Docker 的时候，可能会掉入其中的坑。  
你需要时刻牢记不同的 Docker 镜像运行在不同的环境中。所以当需要容器之间相互通信的时候，比如一个典型 node 后台项目, 你可能需要用到 node, 数据库，nginx 等多个应用程序，
docker 鼓励一个应用一个容器的做法，比如其[官方镜像库](https://hub.docker.com/)中的官方镜像就是这样的，你可以在其中找到[node](https://hub.docker.com/_/node)的镜像,[mysql](https://hub.docker.com/_/mysql)的镜像,[nginx](https://hub.docker.com/_/nginx)的镜像。然后就像我们之前提到的，你可能需要在项目根目录的 `docker-compose.yml` 文件中定义这些镜像的使用，就像下面👇这样：

``` yml
version: '3'
services:
  mysql:
    image: 'mysql:8.0.22'
      # 同一docker network 下的容器可以通过 容器名 相互引用
    container_name: 'mysql'
    networks:
      - ivi_web_net
    environment:
      MYSQL_ALLOW_EMPTY_PASSWORD: 'yes'
      MYSQL_DATABASE: 'admin-server'
    restart: unless-stopped
    volumes:
      - server_data_mysql:/var/lib/mysql  
  server:
    build: ./server
    container_name: 'server'
    depends_on:
      - mysql      
    networks:
      - ivi_web_net
    restart: unless-stopped    
  nginx:
    build: ./nginx
    container_name: 'nginx'
    ports:
      - '8080:8080'
    networks:
      ivi_web_net:
    depends_on:
      - server
    volumes:
      - ./ivi_admin/dist:/var/www/html/admin
      - ./ivi_offical/dist:/var/www/html/offical

networks:
  ivi_web_net:
volumes:
  server_data_mysql:
```
这里为项目定义了三个镜像，里面包括了服务端，数组库，还有 nginx。

现在如果你需要在上面定义的名为 `server` 的 node 容器中连接数据库，那么就可以使用 mysql 数据库容器的 `container_name`: `mysql` 来引用到数据库。

还有一个场景是在容器中想访问宿主机。在 linux 系统中，可以通过 `docker0` 来指代宿主机的 IP 地址，在 PC 或者 Mac 中，则需要通过 `host.docker.internal`这个特殊的 DNS 名称来访问宿主机 IP 地址。 具体请参考 stackoverflow 中的[这个回答](https://stackoverflow.com/questions/31324981/how-to-access-host-port-from-docker-container).

在实际项目中，我们可能需要定义不同的开发环境，比如 development, test, production 等。虽然 Dockerfile 可以多阶段构建。但是我还是觉得 Dockerfile 配置针对不同的环境写在不同的配置文件里比较清晰。所以，我们可能会有一个针对 development 的 `Dockerfile.dev` 配置文件，比如下面👇这样：

``` Dockerfile
FROM node:14.15.1

WORKDIR /usr/app

COPY package.json /usr/app/

RUN npm install --silent --no-cache --registry=https://registry.npm.taobao.org

COPY  ./ ./

CMD ["npm", "start"]

EXPOSE 3000
```

然后我们在 `docker-compose.dev.yml` 中配置如下:

``` yml
version: '3.9'

services:
  web_dev:
    container_name: 'web_dev'
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - '3000:3000'
    volumes:
      - .:/usr/app
```

然后我们在 `package.json` 的 `scripts` 里加上：`"dev:docker": "docker-compose -f docker-compose.dev.yml up"` , 
`"build:docker": "docker-compose up"` ，分别用来启动 `development` 环境容器 和 `prodduct` 环境容器。

到这里项目容器化就完成了。

## 2. 配置 Github Actions

Github Actions 是一套基于事件的 CI/CD 自动化工具。
Github Actions 可以在 Github 仓库里的 Actions 中配置，比如下面👇这样：

``` yml
# This workflow will do a clean install of node dependencies, build the source code and run tests across different versions of node
# For more information see: https://help.github.com/actions/language-and-framework-guides/using-nodejs-with-github-actions

name: Test then Upload Image CI

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Cache node modules
        uses: actions/cache@v2
        env:
          cache-name: cache-node-modules
        with:
          # npm cache files are stored in `~/.npm` on Linux/macOS
          path: ~/.npm
          key: ${{ runner.os }}-build-${{ env.cache-name }}-${{ hashFiles('**/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-build-${{ env.cache-name }}-
            ${{ runner.os }}-build-
            ${{ runner.os }}-
      - name: Install Dependencies
        run: npm install
      - name: Test
        run: npm test
  upload_image:
    runs-on: ubuntu-latest
    needs: test
    steps:
      - name: Set up QEMU
        uses: docker/setup-qemu-action@v1
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v1
      - name: Login to DockerHub
        uses: docker/login-action@v1
        with:
          username: ${{ secrets.DOCKER_HUB_USERNAME }}
          password: ${{ secrets.DOCKER_HUB_ACCESS_TOKEN }}
      - name: Build and push
        id: docker_build
        uses: docker/build-push-action@v2
        with:
          push: true
          tags: andyhuo/docker_with_github_actions_demo:latest
      - name: Image digest
        run: echo ${{ steps.docker_build.outputs.digest }}
```

上面的 Action 定义了在 push 代码的时候，运行两个任务，第一个任务是运行项目测试，如果测试通过那么构建 Docker 镜像并将构建好的镜像上传到 Docker Hub对应的仓库。
需要注意的是，上面配置项中的 `secrets.DOCKER_HUB_USERNAME` 是在 Github 仓库 设置中 `Secrets` 设置项里设置的字段，对应 Docker Hub 账户的用户名，`secrets.DOCKER_HUB_ACCESS_TOKEN` 则是在 Docker Hub 账号设置中 `Security` 设置项里创建的自定义 Token。这里更详细的教程请参考 [Docker 官网](https://docs.docker.com/ci-cd/github-actions/)

## 3. 通过 Docker Hub 的 webhook 触发生产部署

上面的 Github Actions 自动化流程如果运行成功，那么你配置的 Docker Hub 仓库中就会有相应的镜像了。你可以在任何安装了 Docker 的开发环境中，通过 `docker run -d -p 80:80 <project_name> <docker_image>` 来下载镜像，并运行相应的容器。或者也可以通过在 Docker Hub 配置相应的 webhook, 在有新镜像推送到仓库的时候触发自动部署。详细信息请参考 [Docker 官网](https://docs.docker.com/docker-hub/webhooks/)
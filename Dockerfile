FROM node:14.15.1

WORKDIR /usr/app

COPY package.json /usr/app/

RUN npm install --silent --no-cache --registry=https://registry.npm.taobao.org

COPY  ./ ./

RUN npm run build && mv /usr/app/build/* /usr/src && rm -rf /usr/app
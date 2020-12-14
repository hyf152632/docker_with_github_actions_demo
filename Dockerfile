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
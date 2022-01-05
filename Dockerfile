FROM nginx:latest

MAINTAINER Muhammad Azmi Farih "muhazmifarih@gmail.com"

COPY nginx/default.conf /etc/nginx/conf.d/
COPY /dist /usr/share/nginx/html/progressive-weather-app
CMD ["nginx", "-g", "daemon off;"]
EXPOSE 80

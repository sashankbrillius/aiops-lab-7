FROM node:20-alpine

WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm install --omit=dev

COPY src ./src

ENV PORT=5101
EXPOSE 5101

CMD ["node", "src/index.js"]

FROM python:3.11-slim
WORKDIR /app/agent
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
CMD ["python", "-m", "scheduler"]

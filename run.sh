#!/bin/bash
echo ">>> Building and starting the application containers..."
docker-compose up --build -d
echo ""
echo ">>> Application is starting!"
echo ">>> Backend API will be available at http://localhost:5000"
echo ">>> To see logs, run: docker-compose logs -f"
echo ">>> To stop the application, run: docker-compose down"

FROM mcr.microsoft.com/mssql/server:2025-latest
USER root
RUN wget -qO /etc/apt/sources.list.d/mssql-server-2025.list https://packages.microsoft.com/config/ubuntu/24.04/mssql-server-2025.list && apt-get update && apt-get install -y --no-install-recommends mssql-server-fts mssql-server-polybase && rm -rf /var/lib/apt/lists/*
USER mssql
CMD ["/opt/mssql/bin/sqlservr"]

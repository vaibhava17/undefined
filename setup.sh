#!/bin/bash

# Exit on error
set -e

echo "Setting up Database Synchronization Environment..."

# Create project directory
mkdir -p db_sync_project
cd db_sync_project

# Create virtual environment
echo "Creating Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install dependencies
echo "Installing Python dependencies..."
pip install mysql-connector-python pymongo pytest pytest-mock logging

# Create project structure
mkdir -p {src,tests,config,logs}

# Create main synchronization script
cat > src/db_sync.py << 'EOL'
import pymongo
import mysql.connector
from mysql.connector import pooling
from datetime import datetime
import json
from typing import Dict, Any
import logging
from dataclasses import dataclass
from queue import Queue
from threading import Thread
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    filename='logs/sync.log'
)
logger = logging.getLogger(__name__)

@dataclass
class DatabaseConfig:
    """Configuration for database connections"""
    host: str
    user: str
    password: str
    database: str
    port: int = 3306

class DatabaseSynchronizer:
    def __init__(
        self,
        mysql_config: DatabaseConfig,
        mongodb_config: DatabaseConfig,
        batch_size: int = 100,
        sync_interval: float = 1.0
    ):
        self.mysql_config = mysql_config
        self.mongodb_config = mongodb_config
        self.batch_size = batch_size
        self.sync_interval = sync_interval
        self.change_queue = Queue()
        
        self.mysql_pool = self._create_mysql_pool()
        self.mongodb_client = self._connect_mongodb()
        self.last_sync_timestamp = datetime.now()

    # ... [Rest of the DatabaseSynchronizer implementation from previous artifact]
EOL

# Create configuration file
cat > config/config.py << 'EOL'
from dataclasses import dataclass

@dataclass
class Config:
    MYSQL_HOST = "localhost"
    MYSQL_USER = "test_user"
    MYSQL_PASSWORD = "test_password"
    MYSQL_DATABASE = "test_db"
    MYSQL_PORT = 3306

    MONGODB_HOST = "localhost"
    MONGODB_USER = "mongo_user"
    MONGODB_PASSWORD = "mongo_password"
    MONGODB_DATABASE = "test_db"
    MONGODB_PORT = 27017

    BATCH_SIZE = 100
    SYNC_INTERVAL = 1.0
EOL

# Create test file
cat > tests/test_sync.py << 'EOL'
import pytest
from src.db_sync import DatabaseSynchronizer, DatabaseConfig
from datetime import datetime
import pymongo
import mysql.connector

@pytest.fixture
def mysql_config():
    return DatabaseConfig(
        host="localhost",
        user="test_user",
        password="test_password",
        database="test_db",
        port=3306
    )

@pytest.fixture
def mongodb_config():
    return DatabaseConfig(
        host="localhost",
        user="mongo_user",
        password="mongo_password",
        database="test_db",
        port=27017
    )

@pytest.fixture
def synchronizer(mysql_config, mongodb_config):
    return DatabaseSynchronizer(
        mysql_config=mysql_config,
        mongodb_config=mongodb_config,
        batch_size=10,
        sync_interval=0.1
    )

def test_mysql_connection(synchronizer):
    assert synchronizer.mysql_pool is not None

def test_mongodb_connection(synchronizer):
    assert synchronizer.mongodb_client is not None

def test_change_detection(synchronizer, mocker):
    mock_changes = [
        {
            'table_name': 'users',
            'record_id': '1',
            'operation': 'INSERT',
            'new_data': '{"name": "John Doe", "email": "john@example.com"}'
        }
    ]
    mocker.patch.object(
        synchronizer,
        '_get_changes_from_mysql',
        return_value=mock_changes
    )
    
    changes = synchronizer._get_changes_from_mysql(datetime.now())
    assert len(changes) == 1
    assert changes[0]['operation'] == 'INSERT'
EOL

# Create MySQL setup script
cat > setup_mysql.sql << 'EOL'
-- Create test database
CREATE DATABASE IF NOT EXISTS test_db;
USE test_db;

-- Create users table
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255),
    email VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create change_log table
CREATE TABLE IF NOT EXISTS change_log (
    id BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name VARCHAR(255),
    record_id VARCHAR(255),
    operation VARCHAR(10),
    new_data JSON,
    change_timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create trigger for INSERT
DELIMITER //
CREATE TRIGGER after_insert_users
AFTER INSERT ON users
FOR EACH ROW
BEGIN
    INSERT INTO change_log (table_name, record_id, operation, new_data)
    VALUES ('users', NEW.id, 'INSERT', 
        JSON_OBJECT(
            'id', NEW.id,
            'name', NEW.name,
            'email', NEW.email
        )
    );
END;
//

-- Create trigger for UPDATE
CREATE TRIGGER after_update_users
AFTER UPDATE ON users
FOR EACH ROW
BEGIN
    INSERT INTO change_log (table_name, record_id, operation, new_data)
    VALUES ('users', NEW.id, 'UPDATE',
        JSON_OBJECT(
            'id', NEW.id,
            'name', NEW.name,
            'email', NEW.email
        )
    );
END;
//

-- Create trigger for DELETE
CREATE TRIGGER after_delete_users
AFTER DELETE ON users
FOR EACH ROW
BEGIN
    INSERT INTO change_log (table_name, record_id, operation, new_data)
    VALUES ('users', OLD.id, 'DELETE', 
        JSON_OBJECT(
            'id', OLD.id,
            'name', OLD.name,
            'email', OLD.email
        )
    );
END;
//
DELIMITER ;

-- Insert test data
INSERT INTO users (name, email) VALUES
    ('John Doe', 'john@example.com'),
    ('Jane Smith', 'jane@example.com');
EOL

# Create test runner script
cat > run_tests.sh << 'EOL'
#!/bin/bash

# Activate virtual environment
source venv/bin/activate

# Run pytest
pytest tests/ -v
EOL

# Create main runner script
cat > run_sync.sh << 'EOL'
#!/bin/bash

# Activate virtual environment
source venv/bin/activate

# Run synchronization
python src/db_sync.py
EOL

# Make scripts executable
chmod +x run_tests.sh run_sync.sh

# Setup MySQL (assumes MySQL is installed and running)
echo "Setting up MySQL..."
sudo service mysql start
mysql -u root -p < setup_mysql.sql

# Setup MongoDB (assumes MongoDB is installed and running)
echo "Setting up MongoDB..."
sudo service mongodb start
mongosh << 'EOL'
use test_db
db.createUser({
  user: "mongo_user",
  pwd: "mongo_password",
  roles: [{ role: "readWrite", db: "test_db" }]
})
EOL

echo "Setup complete! You can now:"
echo "1. Run tests: ./run_tests.sh"
echo "2. Start synchronization: ./run_sync.sh"
echo "3. Monitor logs: tail -f logs/sync.log"

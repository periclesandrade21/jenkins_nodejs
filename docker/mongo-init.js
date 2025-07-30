// Script de inicialização do MongoDB
db = db.getSiblingDB('test_database');

// Criar usuário para a aplicação
db.createUser({
  user: 'app_user',
  pwd: 'app_password',
  roles: [
    {
      role: 'readWrite',
      db: 'test_database'
    }
  ]
});

// Criar índices necessários
db.status_checks.createIndex({ "timestamp": 1 });
db.status_checks.createIndex({ "client_name": 1 });

print('Database initialized successfully');
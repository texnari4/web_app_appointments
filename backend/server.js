const express = require('express');
const cors = require('cors');
const { Pool } = require('pg');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false,
});

pool.connect((err, client, release) => {
  if (err) {
    return console.error('Ошибка подключения к базе данных:', err.stack);
  }
  client.query('SELECT NOW()', (err, result) => {
    release();
    if (err) {
      return console.error('Ошибка выполнения запроса', err.stack);
    }
    console.log('Успешное подключение к PostgreSQL');
  });
});

app.use(cors());
app.use(express.json());

app.get('/api/health', (req, res) => {
  res.status(200).json({ status: 'OK', message: 'Сервер работает!' });
});

app.get('/api/masters', async (req, res) => {
    try {
        const result = await pool.query('SELECT id, first_name, last_name, specialization FROM masters');
        res.status(200).json(result.rows);
    } catch (error) {
        console.error('Ошибка при получении мастеров:', error);
        res.status(500).json({ message: 'Внутренняя ошибка сервера' });
    }
});

app.post('/api/services', async (req, res) => {
    const { name, description, price, duration_minutes } = req.body;
    if (!name || !price || !duration_minutes) {
        return res.status(400).json({ message: 'Название, цена и длительность являются обязательными полями.' });
    }
    try {
        const newService = await pool.query(
            'INSERT INTO services (name, description, price, duration_minutes) VALUES ($1, $2, $3, $4) RETURNING *',
            [name, description, price, duration_minutes]
        );
        res.status(201).json(newService.rows[0]);
    } catch (error) {
        console.error('Ошибка при создании услуги:', error);
        res.status(500).json({ message: 'Внутренняя ошибка сервера' });
    }
});

app.listen(PORT, () => {
  console.log(`Сервер запущен на порту ${PORT}`);
});

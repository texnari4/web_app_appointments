// api/index.js
export const fetchMasters = async () => {
    try {
        const response = await fetch('/api/masters');
        return await response.json();
    } catch (error) {
        console.error('Ошибка получения мастеров:', error);
    }
};

// Аналогично для услуг, записей и других сущностей


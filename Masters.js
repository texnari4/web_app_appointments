// Masters.js
import { useState, useEffect } from 'react';
import { fetchMasters } from '../api';

const Masters = () => {
    const [masters, setMasters] = useState([]);

    useEffect(() => {
        const loadMasters = async () => {
            const data = await fetchMasters();
            setMasters(data);
        };
        loadMasters();
    }, []);

    return (
        <div className="masters-list">
            {masters.map(master => (
                <div key={master.id} className="master-card">
                    <h3>{master.name}</h3>
                    <p>{master.specialty}</p>
                </div>
            ))}
        </div>
    );
};

export default Masters;

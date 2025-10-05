// AdminLayout.js
import { miniApp, backButton } from '@telegram-apps/sdk-react';

const AdminLayout = ({ children }) => {
    return (
        <div className="admin-layout">
            <header>
                <button onClick={() => backButton.goBack()}>
                    Назад
                </button>
                <h1>Панель администратора</h1>
            </header>
            <main>
                {children}
            </main>
        </div>
    );
};

export default AdminLayout;

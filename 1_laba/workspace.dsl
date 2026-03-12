workspace {
    name "Система управления складом"
    description "Архитектура системы управления складом (Вариант 18), аналог Zoho Inventory"

    model {
        client = person "Клиент" "Управляет товарами, поступлениями и списаниями на складе"
        admin = person "Администратор" "Управляет пользователями, товарами, поступлениями и списаниями на складе"

        warehouse_system = softwareSystem "Система управления складом" "Позволяет управлять товарами, поступлениями, списаниями и пользователями на складе" {
            web_app = container "Web Application" "Предоставляет пользовательский интерфейс для управления складом: просмотр товаров, оформление поступлений, списания" "React, TypeScript" "Web Browser"
            api_gateway = container "API Gateway" "Единая точка входа для всех API-запросов. Маршрутизация, аутентификация и балансировка нагрузки" "Nginx, OpenResty"
            user_service = container "User Service" "Управление пользователями: создание нового пользователя, поиск по логину, поиск по маске имени и фамилии" "Python, FastAPI"
            product_service = container "Product Service" "Управление товарами: добавление товара на склад, поиск по названию, получение остатков, списание товара со склада" "Python, FastAPI"
            receipt_service = container "Receipt Service" "Управление поступлениями: создание поступления товара, получение истории поступлений" "Python, FastAPI"
            notification_service = container "Notification Service" "Обработка и отправка уведомлений пользователям о событиях на складе (поступления, списания, низкие остатки)" "Python, FastAPI"
            user_db = container "User Database" "Хранение данных пользователей: логин, имя, фамилия, email, роль, дата регистрации" "PostgreSQL 15" "Database"
            product_db = container "Product Database" "Хранение данных о товарах: название, описание, категория, единица измерения, текущие остатки на складе" "PostgreSQL 15" "Database"
            receipt_db = container "Receipt Database" "Хранение данных о поступлениях: дата, поставщик, список товаров, количество, стоимость, статус" "PostgreSQL 15" "Database"
            stock_update_topic = container "Stock Update Topic" "Топик для асинхронной передачи событий обновления остатков товаров при поступлении и списании" "Apache Kafka 3.5" "Queue"
            notification_topic = container "Notification Topic" "Топик для асинхронной передачи событий уведомлений пользователям" "Apache Kafka 3.5" "Queue"
        }

        payment_system = softwareSystem "Платежная система" "Внешняя система для регистрации и обработки платежей поставщикам за поступившие товары"
        email_system = softwareSystem "Email система" "Внешняя система для отправки email-уведомлений пользователям о событиях на складе"
        delivery_system = softwareSystem "Система доставки" "Внешняя система для управления доставкой товаров от поставщиков на склад"

        client -> warehouse_system "Управляет товарами, поступлениями и списаниями" "HTTPS"
        admin -> warehouse_system "Управляет пользователями, товарами, поступлениями и списаниями" "HTTPS"
        warehouse_system -> payment_system "Регистрация платежей" "REST HTTPS:443"
        warehouse_system -> email_system "Отправка уведомлений" "SMTP:587"
        warehouse_system -> delivery_system "Управление доставкой товаров" "REST HTTPS:443"

        client -> web_app "Просмотр товаров, оформление поступлений и списаний" "HTTPS:443"
        admin -> web_app "Управление пользователями, товарами, поступлениями и списаниями" "HTTPS:443"

        web_app -> api_gateway "Отправляет API-запросы" "REST HTTPS:443/JSON"

        api_gateway -> user_service "Маршрутизирует запросы управления пользователями: POST /users, GET /users/search" "REST HTTP:8001/JSON"
        api_gateway -> product_service "Маршрутизирует запросы управления товарами: POST /products, GET /products/search, GET /products/stock, DELETE /products/{id}" "REST HTTP:8002/JSON"
        api_gateway -> receipt_service "Маршрутизирует запросы управления поступлениями: POST /receipts, GET /receipts/history" "REST HTTP:8003/JSON"

        user_service -> user_db "Чтение и запись данных пользователей" "SQL/JDBC:5432"
        product_service -> product_db "Чтение и запись данных товаров и остатков" "SQL/JDBC:5432"
        receipt_service -> receipt_db "Чтение и запись данных поступлений и списаний" "SQL/JDBC:5432"

        receipt_service -> stock_update_topic "Публикует события обновления остатков при поступлении товара" "Kafka Protocol:9092"
        stock_update_topic -> product_service "Доставляет события обновления остатков для изменения количества товара" "Kafka Protocol:9092"

        receipt_service -> notification_topic "Публикует события уведомлений о новых поступлениях" "Kafka Protocol:9092"
        notification_topic -> notification_service "Доставляет события для формирования и отправки уведомлений" "Kafka Protocol:9092"

        receipt_service -> payment_system "Регистрация платежа поставщику при оформлении поступления" "REST HTTPS:443/JSON"
        product_service -> delivery_system "Запрос на организацию доставки товара от поставщика" "REST HTTPS:443/JSON"
        notification_service -> email_system "Отправка email-уведомлений пользователям" "SMTP:587"
    }

    views {
        themes default

        systemContext warehouse_system "SystemContext" "Диаграмма контекста системы управления складом" {
            include *
            autoLayout
        }

        container warehouse_system "Containers" "Диаграмма контейнеров системы управления складом" {
            include *
            autoLayout
        }

        dynamic warehouse_system "ReceiptCreation" "Сценарий создания поступления товара на склад" {
            client -> web_app "1. Заполняет форму поступления товара (товар, количество, поставщик, стоимость)"
            web_app -> api_gateway "2. POST /api/receipts {product_id, quantity, supplier, price}"
            api_gateway -> receipt_service "3. Передает запрос на создание поступления"
            receipt_service -> receipt_db "4. Сохраняет данные поступления в базу"
            receipt_service -> payment_system "5. Регистрирует платеж поставщику"
            receipt_service -> stock_update_topic "6. Публикует событие обновления остатков {product_id, +quantity}"
            stock_update_topic -> product_service "7. Доставляет событие обновления остатков"
            product_service -> product_db "8. Увеличивает остаток товара на складе"
            receipt_service -> notification_topic "9. Публикует событие уведомления о поступлении"
            notification_topic -> notification_service "10. Доставляет событие для отправки уведомления"
            notification_service -> email_system "11. Отправляет email-уведомление о поступлении товара"
            autoLayout
        }
    }
}
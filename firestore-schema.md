# Схема Firestore — Wesi Treasury (финансы + прогноз)

Все данные хранятся под пользователем, чтобы каждая компания/аккаунт видела только свои цифры.

```
users/{uid}/finance/account
    currentBalance: number        // текущий баланс "на сегодня"
    currency: string              // напр. "RUB"
    updatedAt: timestamp

users/{uid}/finance/lastForecast          // кэш последнего результата (пишет Cloud Function)
    days_forecast: array
    metrics: object
    computedAt: string (ISO)

users/{uid}/finance/data/transactions/{transactionId}
    date: string        // "YYYY-MM-DD"
    category: string    // напр. "Продажи", "Аренда", "Реклама"
    amount: number      // >0 доход, <0 расход
    note: string?
    createdAt: timestamp

users/{uid}/finance/data/scheduledTransactions/{ruleId}
    amount: number
    category: string
    rule: {
      type: "daily" | "weekly" | "monthly" | "once"
      dayOfMonth?: number     // для monthly, 1-31
      daysOfWeek?: number[]   // для weekly, 0=Вс..6=Сб
      date?: string           // для once, "YYYY-MM-DD"
    }
    startDate: string   // "YYYY-MM-DD", когда правило начинает действовать
    endDate: string?    // необязательно, когда правило перестаёт действовать
    label: string       // напр. "Аренда офиса", "Зарплата команде"

users/{uid}/finance/data/whatIfScenarios/{scenarioId}
    amount: number
    category: string
    rule: { ... }        // тот же формат, что у scheduledTransactions
    active: boolean       // движок учитывает только active == true
    label: string
```

## Правила безопасности (firestore.rules)

```
match /users/{uid}/finance/{document=**} {
  allow read: if request.auth != null && request.auth.uid == uid;
  allow write: if request.auth != null && request.auth.uid == uid
               && document != "lastForecast";
}
```

## Индексы

`transactions` требует составной индекс по `date` (ORDER BY) — Firebase
сам предложит создать его при первом деплое.


---

## users/{uid}/finance/account

Документ с текущим финансовым состоянием пользователя.

```json
{
  "currentBalance": 47250.00,
  "currency": "USD",
  "lastUpdated": "2026-07-28T00:00:00Z",
  "createdAt": "2026-07-28T00:00:00Z"
}
```

| Поле | Тип | Описание |
|------|-----|----------|
| `currentBalance` | double | Текущий баланс счёта |
| `currency` | string | Валюта счёта (default: USD) |
| `lastUpdated` | timestamp | Время последнего обновления |
| `createdAt` | timestamp | Время создания документа |

### Cloud Functions интеграция

- `scheduledLayer` обновляет `currentBalance` при регулярных платежах
- `anomalyFilter` проверяет транзакции на аномалии перед обновлением баланса
- `forecastEngine` использует `currentBalance` как baseline для прогнозов


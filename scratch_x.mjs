import { CARD_CATALOG } from 'file:///C:/Users/jacob/Downloads/Alleyway%20Brawlers/alleyway-brawlers/shared/cards.js';
import { starterRecipe } from 'file:///C:/Users/jacob/Downloads/Alleyway%20Brawlers/alleyway-brawlers/shared/clans.js';
const cs = Object.values(CARD_CATALOG).filter(c => c.clan === 'nebula').sort((a,b)=>a.id.localeCompare(b.id));
for (const c of cs) console.log(c.id.padEnd(15), (c.name||'').padEnd(22), c.cardType.padEnd(12), 'lv'+(c.level||1), 'r'+(c.rarity||1), 'auth'+(c.authority??''), c.base_attack??'', c.base_defense??'', 'promo:'+(c.promotesTo||''));
console.log(JSON.stringify(starterRecipe('nebula')));

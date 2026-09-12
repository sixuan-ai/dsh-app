'use strict';
(() => {
  const form = document.querySelector('#filters');
  const category = document.querySelector('#category');
  const region = document.querySelector('#region');
  const query = document.querySelector('#query');
  const cards = [...document.querySelectorAll('.event')];
  const groups = [...document.querySelectorAll('.year-group')];
  const links = [...document.querySelectorAll('.years a')];
  function filter() {
    const term = query.value.trim().toLocaleLowerCase();
    let count = 0;
    cards.forEach(card => {
      const visible = (category.value === 'all' || card.dataset.category.split(' ').includes(category.value)) &&
        (region.value === 'all' || card.dataset.region === region.value) &&
        (!term || card.textContent.toLocaleLowerCase().includes(term));
      card.hidden = !visible;
      count += Number(visible);
    });
    groups.forEach(group => {
      const count = [...group.querySelectorAll('.event')].filter(card => !card.hidden).length;
      group.hidden = count === 0;
      group.querySelector('h2 span').textContent = `${count} 个节点`;
    });
    links.forEach(link => { link.hidden = document.querySelector(link.getAttribute('href')).hidden; });
    document.querySelector('#result-count').textContent = `${count} 个历史节点 · 从新到旧`;
    document.querySelector('#empty').hidden = count !== 0;
  }
  form.hidden = false;
  form.addEventListener('input', filter);
  form.addEventListener('change', filter);
  form.addEventListener('submit', event => event.preventDefault());
  form.addEventListener('reset', () => setTimeout(filter, 0));
})();
